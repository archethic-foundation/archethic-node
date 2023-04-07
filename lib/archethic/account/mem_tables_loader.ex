defmodule Archethic.Account.MemTablesLoader do
  @moduledoc false

  alias Archethic.{TransactionChain, Crypto, Reward, Account, TransactionChain.Transaction}

  alias Account.MemTables.{TokenLedger, UCOLedger}
  alias Transaction.{ValidationStamp, ValidationStamp.LedgerOperations}
  alias LedgerOperations.{UnspentOutput, TransactionMovement, VersionedUnspentOutput}

  use GenServer
  @vsn Mix.Project.config()[:version]

  require Logger

  @query_fields [
    :address,
    :type,
    :previous_public_key,
    validation_stamp: [
      :timestamp,
      :protocol_version,
      ledger_operations: [:fee, :unspent_outputs, :transaction_movements]
    ]
  ]

  @excluded_types [:oracle, :oracle_summary, :node_shared_secrets, :origin, :on_chain_wallet]

  @spec start_link(args :: list()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec init(args :: list()) :: {:ok, []}
  def init(_args) do
    TransactionChain.list_io_transactions(@query_fields)
    |> Stream.each(&load_transaction(&1, true, _from_init? = true))
    |> Stream.run()

    TransactionChain.list_all(@query_fields)
    |> Stream.reject(&(&1.type in @excluded_types))
    |> Stream.each(&load_transaction(&1, _io_transaction? = false, _from_init? = true))
    |> Stream.run()

    {:ok, []}
  end

  @doc """
  Load the transaction into the memory tables
  """
  @spec load_transaction(Transaction.t(), boolean()) :: :ok
  def load_transaction(
        %Transaction{
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
        io_transaction?,
        from_init? \\ false
      ) do
    unless io_transaction? do
      # when it is not a io_transaction
      previous_address = Crypto.derive_address(previous_public_key)

      UCOLedger.spend_all_unspent_outputs(previous_address, from_init?)
      TokenLedger.spend_all_unspent_outputs(previous_address, from_init?)
    end

    :ok =
      set_transaction_movements(
        address,
        transaction_movements,
        timestamp,
        tx_type,
        protocol_version,
        from_init?
      )

    :ok = set_unspent_outputs(address, unspent_outputs, protocol_version, from_init?)

    Logger.info("Loaded into in memory account tables",
      transaction_address: Base.encode16(address),
      transaction_type: tx_type
    )
  end

  defp set_unspent_outputs(address, unspent_outputs, protocol_version, from_init?) do
    unspent_outputs
    |> Enum.each(fn
      utxo = %UnspentOutput{type: :UCO, amount: amount} when amount > 0 ->
        UCOLedger.add_unspent_output(
          address,
          cast_to_versioned_utxo(utxo, protocol_version),
          from_init?
        )

      utxo = %UnspentOutput{type: {:token, _, _}, amount: amount} when amount > 0 ->
        TokenLedger.add_unspent_output(
          address,
          cast_to_versioned_utxo(utxo, protocol_version),
          from_init?
        )

      _ ->
        # Ignore smart contract calls
        :ignore_haha
    end)
  end

  defp cast_to_versioned_utxo(utxo, protocol_version),
    do: %VersionedUnspentOutput{unspent_output: utxo, protocol_version: protocol_version}

  defp set_transaction_movements(
         address,
         transaction_movements,
         timestamp,
         tx_type,
         protocol_version,
         from_init?
       ) do
    transaction_movements
    |> Enum.filter(&(&1.amount > 0))
    |> Enum.reduce(%{}, &aggregate_movements(&1, &2, address, tx_type, timestamp))
    |> Enum.each(fn
      {{to, :uco}, utxo} ->
        UCOLedger.add_unspent_output(
          to,
          %VersionedUnspentOutput{
            unspent_output: utxo,
            protocol_version: protocol_version
          },
          from_init?
        )

      {{to, _token_address, _token_id}, utxo} ->
        TokenLedger.add_unspent_output(
          to,
          %VersionedUnspentOutput{
            unspent_output: utxo,
            protocol_version: protocol_version
          },
          from_init?
        )
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
end
