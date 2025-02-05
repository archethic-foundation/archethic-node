defmodule Mix.Tasks.Archethic.Db do
  @moduledoc """
  Provide tools to interact with the database

  ## Command line options

  * `--help` - show this help
  * `--clean` - Remove database
  * `--rebuild-utxo` - Rebuild the UTXO database using the transactions stored locally

  @shortdoc "Tools to interact with database"

  """
  alias Archethic.Crypto

  alias Archethic.DB
  alias Archethic.DB.EmbeddedImpl.BootstrapInfo
  alias Archethic.DB.EmbeddedImpl.ChainIndex
  alias Archethic.DB.EmbeddedImpl.P2PView

  alias Archethic.Election

  alias Archethic.P2P

  alias Archethic.Reward

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.UTXO
  alias Archethic.UTXO.DBLedger.FileImpl

  use Mix.Task

  @impl Mix.Task
  @spec run([binary]) :: any
  def run(args) do
    case OptionParser.parse!(args,
           strict: [
             help: :boolean,
             clean: :boolean,
             rebuild_utxo: :boolean
           ]
         ) do
      {[clean: true], _} ->
        clean_db()

      {[rebuild_utxo: true], _} ->
        rebuild_utxo()

      {_, _} ->
        Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
    end
  end

  defp clean_db do
    :archethic
    |> Application.get_env(:root_mut_dir)
    |> File.rm_rf!()

    IO.puts("Database dropped")
  end

  defp rebuild_utxo do
    utxo_dirname = FileImpl.base_path()

    File.cp_r!(
      utxo_dirname,
      utxo_dirname <> "_backup-#{DateTime.utc_now() |> DateTime.to_unix()}"
    )

    resolved_addresses =
      utxo_dirname
      |> File.ls!()
      |> Enum.map(fn filename ->
        genesis = Base.decode16!(filename, case: :mixed)
        {genesis, genesis}
      end)
      |> Map.new()

    File.rm_rf!(utxo_dirname)

    Application.ensure_started(:telemetry)

    # Avoid to index the entire DB, we just need to create the ets table
    ChainIndex.setup_ets_table()

    BootstrapInfo.start_link(path: DB.filepath())
    P2PView.start_link(path: DB.filepath())

    PartitionSupervisor.start_link(
      child_spec: Task.Supervisor,
      name: Archethic.TaskSupervisors
    )

    Registry.start_link(keys: :duplicate, name: Archethic.PubSubRegistry)

    TransactionChain.Supervisor.start_link()
    Crypto.Supervisor.start_link([])
    P2P.Supervisor.start_link()
    UTXO.Supervisor.start_link()
    Reward.Supervisor.start_link()

    P2P.list_nodes() |> P2P.connect_nodes()

    :ets.new(:sorted_transactions, [:named_table, :ordered_set, :public])

    # Get the addresses from the transaction chains
    t1 =
      Task.async(fn ->
        DB.list_genesis_addresses()
        |> Stream.flat_map(&list_chain_addresses/1)
        |> Stream.each(fn {address, timestamp, genesis_address} ->
          :ets.insert(
            :sorted_transactions,
            {{DateTime.to_unix(timestamp, :millisecond), address}, {:chain, genesis_address}}
          )
        end)
        |> Stream.run()
      end)

    # Get the addresses from the IO transactions
    t2 =
      Task.async(fn ->
        DB.list_io_transactions([])
        |> Stream.each(
          fn tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: timestamp}} ->
            :ets.insert(
              :sorted_transactions,
              {{DateTime.to_unix(timestamp, :millisecond), tx}, :io}
            )
          end
        )
        |> Stream.run()
      end)

    IO.puts("== Listing transactions to ingest ==")
    Task.await_many([t1, t2], :infinity)

    # Scan the ets table in order to rebuild the UTXO db
    IO.puts("== Rebuilding of the UTXO == ")

    authorized_nodes = P2P.authorized_and_available_nodes()

    %{ingest_task: ingest_task} =
      :ets.tab2list(:sorted_transactions)
      |> Enum.chunk_every(2000)
      |> Enum.reduce(
        %{ingest_task: nil, resolved_addresses: resolved_addresses},
        fn addresses, %{ingest_task: ingest_task, resolved_addresses: resolved_addresses} ->
          txs =
            Task.async_stream(addresses, &fetch_transaction(&1, authorized_nodes),
              timeout: 20_000,
              max_concurrency: 16
            )
            |> Enum.map(fn {:ok, res} -> res end)

          new_resolved_addresses =
            txs
            |> Enum.map(fn {_, tx} -> tx end)
            |> resolve_genesis(resolved_addresses, authorized_nodes)

          # Await previous ingestion task to keep chronologix ingestion
          if ingest_task != nil, do: Task.await(ingest_task, :infinity)

          new_ingest_task = Task.async(fn -> ingest_transactions(txs, new_resolved_addresses) end)

          %{ingest_task: new_ingest_task, resolved_addresses: new_resolved_addresses}
        end
      )

    Task.await(ingest_task, :infinity)

    IO.puts("== Rebuilding finished ==")
  end

  defp list_chain_addresses(genesis_address) do
    ChainIndex.list_chain_addresses(genesis_address, DB.filepath())
    # Remove 0 address as it does not exists
    |> Stream.reject(fn {address, _} -> :binary.decode_unsigned(address) == 0 end)
    |> Stream.map(fn {address, timestamp} -> {address, timestamp, genesis_address} end)
    |> Enum.to_list()
  end

  defp fetch_transaction({{_, address}, {:chain, genesis_address}}, authorized_nodes) do
    nodes = Election.chain_storage_nodes(address, authorized_nodes)

    {:ok, tx} =
      TransactionChain.fetch_transaction(address, nodes,
        timeout: 18_000,
        acceptance_resolver: :accept_transaction
      )

    {genesis_address, tx}
  end

  defp fetch_transaction({{_, tx}, :io}, _), do: {nil, tx}

  defp resolve_genesis(txs, resolved_addresses, authorized_nodes) do
    txs
    |> get_addresses_to_resolve()
    |> Enum.reject(&Map.has_key?(resolved_addresses, &1))
    |> Task.async_stream(
      fn address ->
        nodes = Election.chain_storage_nodes(address, authorized_nodes)
        {:ok, genesis} = TransactionChain.fetch_genesis_address(address, nodes)
        {address, genesis}
      end,
      max_concurrency: 16
    )
    |> Stream.map(fn {:ok, res} -> res end)
    |> Map.new()
    |> Map.merge(resolved_addresses)
  end

  defp get_addresses_to_resolve(txs) do
    txs
    |> Enum.flat_map(fn
      %Transaction{validation_stamp: %ValidationStamp{protocol_version: protocol_version}}
      when protocol_version > 7 ->
        []

      %Transaction{
        validation_stamp: %ValidationStamp{
          recipients: recipients,
          ledger_operations: %LedgerOperations{transaction_movements: movements}
        }
      } ->
        movements |> Enum.map(& &1.to) |> Enum.concat(recipients) |> Enum.uniq()
    end)
    |> Enum.uniq()
  end

  defp ingest_transactions(txs, resolved_addresses) do
    Enum.each(txs, fn
      {nil, tx} ->
        UTXO.load_transaction(tx,
          skip_consume_inputs?: true,
          skip_verify_consumed?: true,
          resolved_addresses: resolved_addresses
        )

      {_genesis, tx} ->
        UTXO.load_transaction(tx,
          skip_verify_consumed?: true,
          resolved_addresses: resolved_addresses
        )
    end)
  end
end
