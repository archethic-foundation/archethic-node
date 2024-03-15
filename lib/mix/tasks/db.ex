defmodule Mix.Tasks.Archethic.Db do
  @moduledoc """
  Provide tools to interact with the database

  ## Command line options

  * `--help` - show this help
  * `--clean` - Remove database
  * `--rebuild-utxo` - Rebuild the UTXO database using the transactions stored locally

  @shortdoc "Tools to interact with database"

  """
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
    File.cp_r!(
      Archethic.UTXO.DBLedger.FileImpl.base_path(),
      Archethic.UTXO.DBLedger.FileImpl.base_path() <>
        "_backup-#{DateTime.utc_now() |> DateTime.to_unix()}"
    )

    File.rm_rf!(Archethic.UTXO.DBLedger.FileImpl.base_path())

    Application.ensure_started(:telemetry)

    # Avoid to index the entire DB, we just need to create the ets table
    Archethic.DB.EmbeddedImpl.ChainIndex.setup_ets_table()

    Archethic.DB.EmbeddedImpl.BootstrapInfo.start_link(path: Archethic.DB.filepath())
    Archethic.DB.EmbeddedImpl.P2PView.start_link(path: Archethic.DB.filepath())

    Task.Supervisor.start_link(name: Archethic.TaskSupervisor)
    Registry.start_link(keys: :duplicate, name: Archethic.PubSubRegistry)

    Archethic.TransactionChain.Supervisor.start_link()
    Archethic.Crypto.Supervisor.start_link([])
    Archethic.Election.Supervisor.start_link([])
    Archethic.P2P.Supervisor.start_link()
    Archethic.UTXO.Supervisor.start_link()
    Archethic.Reward.Supervisor.start_link()

    Archethic.P2P.list_nodes() |> Archethic.P2P.connect_nodes()

    :ets.new(:sorted_transactions, [:named_table, :ordered_set, :public])

    # Get the addresses from the transaction chains
    t1 =
      Task.async(fn ->
        Archethic.DB.list_genesis_addresses()
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
        Archethic.DB.list_io_transactions([:address, validation_stamp: [:timestamp]])
        |> Stream.each(fn %Archethic.TransactionChain.Transaction{
                            address: address,
                            validation_stamp:
                              %Archethic.TransactionChain.Transaction.ValidationStamp{
                                timestamp: timestamp
                              }
                          } ->
          :ets.insert(
            :sorted_transactions,
            {{DateTime.to_unix(timestamp, :millisecond), address}, :io}
          )
        end)
        |> Stream.run()
      end)

    IO.puts("== Listing transactions to ingest ==")
    Task.await_many([t1, t2], :infinity)

    # Scan the ets table in order to rebuild the UTXO db
    IO.puts("== Rebuilding of the UTXO == ")

    :ets.foldl(
      fn
        {{_, address}, {:chain, genesis_address}}, _acc ->
          {:ok, tx} = Archethic.DB.get_transaction(address, [], :chain)
          Archethic.UTXO.load_transaction(tx, genesis_address)

        {{_, address}, :io}, _acc ->
          {:ok, tx} = Archethic.DB.get_transaction(address, [], :io)
          Archethic.UTXO.load_transaction(tx, <<>>, skip_consume_inputs?: true)
      end,
      nil,
      :sorted_transactions
    )

    IO.puts("== Rebuilding finished ==")
  end

  defp list_chain_addresses(genesis_address) do
    Archethic.DB.EmbeddedImpl.ChainIndex.list_chain_addresses(
      genesis_address,
      Archethic.DB.filepath()
    )
    |> Stream.map(fn {address, timestamp} -> {address, timestamp, genesis_address} end)
    |> Enum.to_list()
  end
end
