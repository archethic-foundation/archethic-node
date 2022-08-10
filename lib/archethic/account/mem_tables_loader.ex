defmodule Archethic.Account.MemTablesLoader do
  @moduledoc false

  use GenServer

  alias Archethic.Account.MemTables.TokenLedger
  alias Archethic.Account.MemTables.UCOLedger

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.Utils

  require Logger

  alias Archethic.Reward

  @query_fields [
    :address,
    :type,
    :previous_public_key,
    validation_stamp: [
      :timestamp,
      ledger_operations: [:fee, :unspent_outputs, :transaction_movements]
    ]
  ]

  @excluded_types [
    :node,
    :oracle,
    :oracle_summary,
    :node_shared_secrets,
    :origin,
    :on_chain_wallet
  ]

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    TransactionChain.list_all(@query_fields)
    |> Stream.reject(&(&1.type in @excluded_types))
    |> Stream.each(&load_transaction/1)
    |> Stream.run()

    {:ok, []}
  end

  @doc """
  Load the transaction into the memory tables
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{
        address: address,
        type: tx_type,
        previous_public_key: previous_public_key,
        validation_stamp: %ValidationStamp{
          timestamp: timestamp,
          ledger_operations: %LedgerOperations{
            fee: fee,
            unspent_outputs: unspent_outputs,
            transaction_movements: transaction_movements
          }
        }
      }) do
    previous_address = Crypto.derive_address(previous_public_key)

    UCOLedger.spend_all_unspent_outputs(previous_address)
    TokenLedger.spend_all_unspent_outputs(previous_address)

    burn_storage_nodes =
      Election.storage_nodes(LedgerOperations.burning_address(), P2P.authorized_nodes(timestamp))

    transaction_movements =
      if Utils.key_in_node_list?(burn_storage_nodes, Crypto.first_node_public_key()) and
           fee > 0 do
        [
          %TransactionMovement{
            to: LedgerOperations.burning_address(),
            amount: fee,
            type: :UCO
          }
          | transaction_movements
        ]
      else
        transaction_movements
      end

    :ok = set_transaction_movements(address, transaction_movements, timestamp, tx_type)
    :ok = set_unspent_outputs(address, unspent_outputs, timestamp)

    Logger.info("Loaded into in memory account tables",
      transaction_address: Base.encode16(address),
      transaction_type: tx_type
    )
  end

  defp set_unspent_outputs(address, unspent_outputs, timestamp) do
    unspent_outputs
    |> Enum.filter(&(&1.amount > 0))
    |> Enum.each(fn
      unspent_output = %UnspentOutput{type: :UCO} ->
        UCOLedger.add_unspent_output(address, unspent_output, timestamp)

      unspent_output = %UnspentOutput{type: {:token, _token_address, _token_id}} ->
        TokenLedger.add_unspent_output(address, unspent_output, timestamp)
    end)
  end

  defp set_transaction_movements(address, transaction_movements, timestamp, tx_type) do
    transaction_movements
    |> Enum.filter(&(&1.amount > 0))
    |> Enum.reduce(%{}, &aggregate_movements(&1, &2, address, tx_type))
    |> Enum.each(fn
      {{to, :uco}, utxo} ->
        UCOLedger.add_unspent_output(to, utxo, timestamp)

      {{to, _token_address}, utxo} ->
        TokenLedger.add_unspent_output(to, utxo, timestamp)
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
    ...>  ] |> Enum.reduce(%{}, fn mov,acc -> MemTablesLoader.aggregate_movements(mov, acc, "@Bob1","") end)
    %{
      {"@Hugo1", :uco} =>      %UnspentOutput{from: "@Bob1", amount: 900_000_000, type: :UCO},
      {"@Tom1", :uco} =>       %UnspentOutput{from: "@Bob1", amount: 1_500_000_000, type: :UCO},
      {"@Alice1", :uco} =>     %UnspentOutput{from: "@Bob1", amount: 500_000_000, type: :UCO},
      {"@Hugo1", "@AEUSD"} =>  %UnspentOutput{from: "@Bob1", amount: 600_000_000,  type: {:token, "@AEUSD", 0}},
      {"@Tom1", "@AEUSD"} =>   %UnspentOutput{from: "@Bob1", amount: 400_000_000,  type: {:token, "@AEUSD", 0}},
      {"@Alice3", "@AEUSD"} => %UnspentOutput{from: "@Bob1", amount: 200_000_000,  type: {:token, "@AEUSD", 0}},
      {"@Hugo1", "@ColorNFT", 1} => %UnspentOutput{from: "@Bob1", amount: 100_000_000,  type: {:token, "@ColorNFT", 1}},
      {"@Hugo1", "@ColorNFT",2} => %UnspentOutput{from: "@Bob1", amount: 100_000_000,  type: {:token, "@ColorNFT", 2}},
      {"@Tom5", "@ColorNFT",3} => %UnspentOutput{from: "@Bob1", amount: 100_000_000,  type: {:token, "@ColorNFT", 3}},
      {"@Tom5", "@ColorNFT",4} => %UnspentOutput{from: "@Bob1", amount: 100_000_000,  type: {:token, "@ColorNFT", 4}},
      {"@Alice7", "@ColorNFT",5} => %UnspentOutput{from: "@Bob1", amount: 100_000_000,  type: {:token, "@ColorNFT", 5}},
      {"@Alice7", "@ColorNFT",6} => %UnspentOutput{from: "@Bob1", amount: 100_000_000,  type: {:token, "@ColorNFT", 6}},
    }

    iex> [
    ...>   %TransactionMovement{to: "@Hugo1", amount: 200_000_000, type: {:token, "@RewardToken0", 0}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 200_000_000, type: {:token, "@RewardToken0", 0}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 200_000_000, type: {:token, "@RewardToken1", 0}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 200_000_000, type: {:token, "@RewardToken2", 0}},
    ...>   %TransactionMovement{to: "@Hugo1", amount: 300_000_000, type: {:token, "@RewardToken2", 0}},
    ...>  ] |> Enum.reduce(%{}, fn mov,acc -> MemTablesLoader.aggregate_movements(mov, acc, "@Bob1","") end)
    %{
      {"@Hugo1", :uco} =>      %UnspentOutput{from: "@Bob1", amount: 1_100_000_000, type: :UCO},
    }
  """
  def aggregate_movements(movement, acc, address, tx_type) do
    case movement do
      %TransactionMovement{to: to, amount: amount, type: :UCO} ->
        new_utxo = %UnspentOutput{amount: amount, from: address, type: :UCO}

        Map.update(
          acc,
          {to, :uco},
          new_utxo,
          &%UnspentOutput{amount: &1.amount + amount, from: address, type: :UCO}
        )

      %TransactionMovement{to: to, amount: amount, type: {:token, token_address, 0}} ->
        if Reward.is_reward_token?(token_address) && tx_type != :node_rewards do
          new_utxo = %UnspentOutput{amount: amount, from: address, type: :UCO}

          Map.update(
            acc,
            {to, :uco},
            new_utxo,
            &%UnspentOutput{amount: &1.amount + amount, from: address, type: :UCO}
          )
        else
          new_utxo = %UnspentOutput{
            amount: amount,
            from: address,
            type: {:token, token_address, 0}
          }

          Map.update(
            acc,
            {to, token_address},
            new_utxo,
            &%UnspentOutput{
              amount: &1.amount + amount,
              from: address,
              type: {:token, token_address, 0}
            }
          )
        end

      %TransactionMovement{to: to, amount: amount, type: {:token, token_address, token_id}} ->
        new_utxo = %UnspentOutput{
          amount: amount,
          from: address,
          type: {:token, token_address, token_id}
        }

        Map.put(acc, {to, token_address, token_id}, new_utxo)
    end
  end
end
