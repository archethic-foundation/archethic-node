defmodule Archethic.Account.MemTablesLoader do
  @moduledoc false

  use GenServer
  @vsn 1

  alias Archethic.Account.MemTables.GenesisInputLedger
  alias Archethic.Account.MemTables.TokenLedger
  alias Archethic.Account.MemTables.UCOLedger
  alias Archethic.Account.MemTables.StateLedger

  alias Archethic.Account.GenesisPendingLog
  alias Archethic.Account.GenesisState

  alias Archethic.Crypto

  alias Archethic.DB

  alias Archethic.Election

  alias Archethic.P2P

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.Utils

  require Logger

  alias Archethic.Reward

  @query_fields [
    :address,
    :type,
    :previous_public_key,
    validation_stamp: [
      :timestamp,
      :protocol_version,
      ledger_operations: [:fee, :unspent_outputs, :transaction_movements, :consumed_inputs]
    ]
  ]

  @excluded_types [
    :oracle,
    :oracle_summary,
    :node_shared_secrets,
    :origin,
    :keychain,
    :keychain_access
  ]

  @spec start_link(args :: list()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    TransactionChain.list_io_transactions(@query_fields)
    |> Stream.each(
      &load_transaction(&1,
        io_transaction?: true,
        load_genesis?: false
      )
    )
    |> Stream.run()

    TransactionChain.list_all(@query_fields)
    |> Stream.reject(&(&1.type in @excluded_types))
    |> Stream.each(
      &load_transaction(&1,
        io_transaction?: false,
        load_genesis?: false
      )
    )
    |> Stream.run()

    # After AEIP-21 phase2 all the lines above could be truncated, as the listing will come from the genesis states & logs
    # Reducing the time of node's startup
    load_genesis_ledger()

    {:ok, %{}}
  end

  @type load_options :: [
          io_transaction?: boolean(),
          load_genesis?: boolean()
        ]

  @doc """
  Load the transaction into the memory tables
  """
  @spec load_transaction(Transaction.t(), load_options()) :: :ok
  def load_transaction(
        tx = %Transaction{
          address: address,
          type: tx_type,
          previous_public_key: previous_public_key,
          validation_stamp: %ValidationStamp{
            timestamp: timestamp,
            protocol_version: protocol_version,
            ledger_operations: %LedgerOperations{
              unspent_outputs: unspent_outputs,
              transaction_movements: transaction_movements
            }
          }
        },
        opts \\ []
      )
      when is_list(opts) do
    io_transaction? = Keyword.get(opts, :io_transaction?, false)
    load_genesis? = Keyword.get(opts, :load_genesis?, true)

    unless io_transaction? do
      previous_address = Crypto.derive_address(previous_public_key)

      UCOLedger.spend_all_unspent_outputs(previous_address)
      TokenLedger.spend_all_unspent_outputs(previous_address)
      StateLedger.spend_all_unspent_outputs(previous_address)
    end

    :ok =
      set_transaction_movements(
        address,
        transaction_movements,
        timestamp,
        tx_type,
        protocol_version
      )

    :ok = set_unspent_outputs(address, unspent_outputs, protocol_version)

    if load_genesis? do
      GenServer.call(__MODULE__, {:load_genesis, tx, io_transaction?})
    end

    Logger.info("Loaded into in memory account tables",
      transaction_address: Base.encode16(address),
      transaction_type: tx_type
    )
  end

  defp set_unspent_outputs(address, unspent_outputs, protocol_version) do
    unspent_outputs
    |> Enum.filter(&(&1.amount > 0))
    |> Enum.map(fn unspent_output ->
      %VersionedUnspentOutput{
        unspent_output: unspent_output,
        protocol_version: protocol_version
      }
    end)
    |> Enum.each(fn
      unspent_output = %VersionedUnspentOutput{unspent_output: %UnspentOutput{type: :UCO}} ->
        UCOLedger.add_unspent_output(address, unspent_output)

      unspent_output = %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          type: {:token, _token_address, _token_id}
        }
      } ->
        TokenLedger.add_unspent_output(address, unspent_output)

      unspent_output = %VersionedUnspentOutput{unspent_output: %UnspentOutput{type: :state}} ->
        StateLedger.add_unspent_output(address, unspent_output)

      _ ->
        # Ignore smart contract calls
        :ignore
    end)
  end

  defp set_transaction_movements(
         address,
         transaction_movements,
         timestamp,
         tx_type,
         protocol_version
       ) do
    transaction_movements
    |> Enum.filter(&(&1.amount > 0))
    |> Enum.reduce(%{}, &aggregate_movements(&1, &2, address, tx_type, timestamp))
    |> Enum.each(fn
      {{to, :uco}, utxo} ->
        UCOLedger.add_unspent_output(to, %VersionedUnspentOutput{
          unspent_output: utxo,
          protocol_version: protocol_version
        })

      {{to, _token_address, _token_id}, utxo} ->
        TokenLedger.add_unspent_output(to, %VersionedUnspentOutput{
          unspent_output: utxo,
          protocol_version: protocol_version
        })
    end)
  end

  @doc """
    Aggregate movements into Single utxo based on to ,
    and to , token address

    iex> [
    ...>   %TransactionMovement{to: "@Hugo1", amount: 100_000_000, type: :UCO},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 200_000_000, type: :UCO},
    ...>   %TransactionMovement{to: "@Tom1", amount: 600_000_000, type: :UCO},
    ...>   %TransactionMovement{to: "@Tom1", amount: 500_000_000, type: :UCO},
    ...>   %TransactionMovement{to: "@Alice1", amount: 500_000_000, type: :UCO},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 200_000_000, type: {:token, "@AEUSD", 0}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 200_000_000, type: {:token, "@RewardToken1", 0}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 200_000_000, type: {:token, "@RewardToken1", 0}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 200_000_000, type: {:token, "@RewardToken2", 0}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 400_000_000, type: {:token, "@AEUSD", 0}},
    ...>   %TransactionMovement{to: "@Tom1",  amount: 200_000_000, type: {:token, "@AEUSD", 0}},
    ...>   %TransactionMovement{to: "@Tom1",  amount: 200_000_000, type: {:token, "@AEUSD", 0}},
    ...>   %TransactionMovement{to: "@Tom1",  amount: 200_000_000, type: {:token, "@RewardToken1", 0}},
    ...>   %TransactionMovement{to: "@Tom1",  amount: 200_000_000, type: {:token, "@RewardToken2", 0}},
    ...>   %TransactionMovement{to: "@Alice3",  amount: 200_000_000, type: {:token, "@AEUSD", 0}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 100_000_000, type: {:token, "@ColorNFT", 1}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 100_000_000, type: {:token, "@ColorNFT", 2}},
    ...>   %TransactionMovement{to: "@Tom5", amount: 100_000_000, type: {:token, "@ColorNFT", 3}},
    ...>   %TransactionMovement{to: "@Tom5", amount: 100_000_000, type: {:token, "@ColorNFT", 4}},
    ...>   %TransactionMovement{to: "@Alice7", amount: 100_000_000, type: {:token, "@ColorNFT", 5}},
    ...>   %TransactionMovement{to: "@Alice7", amount: 100_000_000, type: {:token, "@ColorNFT", 6}}
    ...>  ] |> Enum.reduce(%{}, fn mov,acc -> MemTablesLoader.aggregate_movements(mov, acc, "@Bob1","",~U[2022-10-11 09:24:01.879Z]) end)
    %{
      {"@Hugo1", :uco} =>      %UnspentOutput{from: "@Bob1", amount: 900_000_000, type: :UCO,timestamp: ~U[2022-10-11 09:24:01.879Z]},
      {"@Tom1", :uco} =>       %UnspentOutput{from: "@Bob1", amount: 1_500_000_000, type: :UCO,timestamp: ~U[2022-10-11 09:24:01.879Z]},
      {"@Hugo1", "@ColorNFT", 1} => %UnspentOutput{from: "@Bob1", amount: 100_000_000,  type: {:token, "@ColorNFT", 1},timestamp: ~U[2022-10-11 09:24:01.879Z]},
      {"@Alice1", :uco} =>     %UnspentOutput{from: "@Bob1", amount: 500_000_000, type: :UCO,timestamp: ~U[2022-10-11 09:24:01.879Z]},
      {"@Hugo1", "@AEUSD", 0} =>  %UnspentOutput{from: "@Bob1", amount: 600_000_000,  type: {:token, "@AEUSD", 0},timestamp: ~U[2022-10-11 09:24:01.879Z]},
      {"@Tom1", "@AEUSD", 0} =>   %UnspentOutput{from: "@Bob1", amount: 400_000_000,  type: {:token, "@AEUSD", 0},timestamp: ~U[2022-10-11 09:24:01.879Z]},
      {"@Alice3", "@AEUSD", 0} => %UnspentOutput{from: "@Bob1", amount: 200_000_000,  type: {:token, "@AEUSD", 0},timestamp: ~U[2022-10-11 09:24:01.879Z]},
      {"@Hugo1", "@ColorNFT",2} => %UnspentOutput{from: "@Bob1", amount: 100_000_000,  type: {:token, "@ColorNFT", 2},timestamp: ~U[2022-10-11 09:24:01.879Z]},
      {"@Tom5", "@ColorNFT",3} => %UnspentOutput{from: "@Bob1", amount: 100_000_000,  type: {:token, "@ColorNFT", 3},timestamp: ~U[2022-10-11 09:24:01.879Z]},
      {"@Tom5", "@ColorNFT",4} => %UnspentOutput{from: "@Bob1", amount: 100_000_000,  type: {:token, "@ColorNFT", 4},timestamp: ~U[2022-10-11 09:24:01.879Z]},
      {"@Alice7", "@ColorNFT",5} => %UnspentOutput{from: "@Bob1", amount: 100_000_000,  type: {:token, "@ColorNFT", 5},timestamp: ~U[2022-10-11 09:24:01.879Z]},
      {"@Alice7", "@ColorNFT",6} => %UnspentOutput{from: "@Bob1", amount: 100_000_000,  type: {:token, "@ColorNFT", 6},timestamp: ~U[2022-10-11 09:24:01.879Z]},
    }

    iex> [
    ...>   %TransactionMovement{to: "@Hugo1", amount: 200_000_000, type: {:token, "@RewardToken0", 0}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 200_000_000, type: {:token, "@RewardToken0", 0}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 200_000_000, type: {:token, "@RewardToken1", 0}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 200_000_000, type: {:token, "@RewardToken2", 0}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 300_000_000, type: {:token, "@RewardToken2", 0}},
    ...>  ] |> Enum.reduce(%{}, fn mov,acc -> MemTablesLoader.aggregate_movements(mov, acc, "@Bob1","",~U[2022-10-11 09:24:01.879Z]) end)
    %{
      {"@Hugo1", :uco} =>      %UnspentOutput{from: "@Bob1", amount: 1_100_000_000, type: :UCO,timestamp: ~U[2022-10-11 09:24:01.879Z]},
    }
  """
  def aggregate_movements(movement, acc, address, tx_type, timestamp) do
    case movement do
      %TransactionMovement{to: to, amount: amount, type: :UCO} ->
        new_utxo = %UnspentOutput{amount: amount, from: address, type: :UCO, timestamp: timestamp}

        Map.update(
          acc,
          {to, :uco},
          new_utxo,
          &%UnspentOutput{
            amount: &1.amount + amount,
            from: address,
            type: :UCO,
            timestamp: timestamp
          }
        )

      %TransactionMovement{to: to, amount: amount, type: {:token, token_address, 0}} ->
        # Since issue #1368 Reward token are converted to UCO directly in validation
        # but to keep retrocompatibility with old transaction we need to keep this
        # control when loading UTXO mainly for self repair
        if Reward.is_reward_token?(token_address) && tx_type != :node_rewards do
          new_utxo = %UnspentOutput{
            amount: amount,
            from: address,
            type: :UCO,
            timestamp: timestamp
          }

          Map.update(
            acc,
            {to, :uco},
            new_utxo,
            &%UnspentOutput{
              amount: &1.amount + amount,
              from: address,
              type: :UCO,
              timestamp: timestamp
            }
          )
        else
          new_utxo = %UnspentOutput{
            amount: amount,
            from: address,
            type: {:token, token_address, 0},
            timestamp: timestamp
          }

          Map.update(
            acc,
            {to, token_address, 0},
            new_utxo,
            &%UnspentOutput{
              amount: &1.amount + amount,
              from: address,
              type: {:token, token_address, 0},
              timestamp: timestamp
            }
          )
        end

      %TransactionMovement{to: to, amount: amount, type: {:token, token_address, token_id}} ->
        new_utxo = %UnspentOutput{
          amount: amount,
          from: address,
          type: {:token, token_address, token_id},
          timestamp: timestamp
        }

        Map.put(acc, {to, token_address, token_id}, new_utxo)
    end
  end

  defp load_genesis_ledger do
    File.mkdir_p!(GenesisPendingLog.base_path())
    File.mkdir_p!(GenesisState.base_path())

    Utils.mut_dir("genesis/*{state,pending}/*")
    |> Path.wildcard()
    |> Task.async_stream(fn file ->
      genesis_address = file |> Path.basename() |> Base.decode16!()

      if String.match?(file, ~r/^genesis\/state.*$/) do
        load_genesis_state(genesis_address)
      end

      if String.match?(file, ~r/^genesis\/pending.*$/) do
        load_genesis_log(genesis_address)
      end
    end)
    |> Stream.run()
  end

  defp load_genesis_state(genesis_address) do
    inputs = GenesisState.fetch(genesis_address)
    GenesisInputLedger.load_inputs(genesis_address, inputs)
  end

  defp load_genesis_log(genesis_address) do
    genesis_address
    |> GenesisPendingLog.stream()
    |> Enum.each(fn input ->
      GenesisInputLedger.add_chain_input(genesis_address, input)
    end)
  end

  def handle_call(
        {:load_genesis,
         tx = %Transaction{
           address: address,
           validation_stamp: %ValidationStamp{
             timestamp: timestamp,
             ledger_operations: %LedgerOperations{
               transaction_movements: transaction_movements,
               consumed_inputs: consumed_inputs
             },
             protocol_version: protocol_version
           }
         }, io_transaction?},
        _,
        state
      ) do
    authorized_nodes = P2P.authorized_and_available_nodes()

    # Ingest all the movements to fill up the UTXO list
    Enum.each(
      transaction_movements,
      &ingest_genesis_inputs(&1, address, timestamp, authorized_nodes, protocol_version)
    )

    case find_genesis_address(tx) do
      {:ok, genesis_address} ->
        # We need to determine whether the node is responsible of the chain genesis pool as the transaction have been received as an I/O transaction.
        chain_transaction? =
          (not io_transaction? or TransactionChain.get_size(genesis_address) > 0) and
            genesis_node?(genesis_address, authorized_nodes)

        # In case, this transaction is one of the genesis chains, we have to consume inputs
        if chain_transaction? and length(consumed_inputs) > 0 do
          consume_genesis_inputs(genesis_address, tx)
        end

      _ ->
        :ignore
    end

    {:reply, :ok, state}
  end

  defp find_genesis_address(tx = %Transaction{address: address}) do
    case DB.find_genesis_address(address) do
      {:ok, genesis_address} ->
        # This happens when the last transaction is ingested in the system (i.e last's tx chain)
        {:ok, genesis_address}

      {:error, :not_found} ->
        # This might happens when the transaction haven't been yet synchronized but the previous transaction is already in the system (i.e genesis's chain)
        DB.find_genesis_address(Transaction.previous_address(tx))
    end
  end

  defp genesis_node?(genesis_address, nodes) do
    genesis_nodes = Election.chain_storage_nodes(genesis_address, nodes)
    Utils.key_in_node_list?(genesis_nodes, Crypto.first_node_public_key())
  end

  defp ingest_genesis_inputs(
         %TransactionMovement{to: to, amount: amount, type: type},
         tx_address,
         tx_timestamp,
         authorized_nodes,
         protocol_version
       ) do
    tx_input = %VersionedTransactionInput{
      input: %TransactionInput{
        from: tx_address,
        amount: amount,
        timestamp: tx_timestamp,
        type: type
      },
      protocol_version: protocol_version
    }

    # We need to determine whether the node is responsible of the transaction movements destination genesis pool
    case DB.find_genesis_address(to) do
      {:ok, genesis_address} ->
        if genesis_node?(genesis_address, authorized_nodes) do
          GenesisPendingLog.append(genesis_address, tx_input)
          GenesisInputLedger.add_chain_input(genesis_address, tx_input)
        end

      _ ->
        # Support when the resolved address is the genesis address
        if genesis_node?(to, authorized_nodes) do
          GenesisPendingLog.append(to, tx_input)
          GenesisInputLedger.add_chain_input(to, tx_input)
        end
    end
  end

  defp consume_genesis_inputs(genesis_address, tx = %Transaction{}) do
    # We update the UTXOs by using the consumed inputs by the transaction
    GenesisInputLedger.update_chain_inputs(tx, genesis_address)
    utxos = GenesisInputLedger.get_unspent_inputs(genesis_address)

    # We flush the serialized state of the genesis UTXOs
    GenesisState.persist(genesis_address, utxos)

    # Once the state have been serialized, we can clean the pending log of inputs
    GenesisPendingLog.clear(genesis_address)
  end
end
