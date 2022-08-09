defmodule Archethic.Reward do
  @moduledoc """
  Module which handles the rewards and transfer scheduling
  """

  alias Archethic.OracleChain

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.Account

  alias Archethic.SharedSecrets

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias __MODULE__.Scheduler

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer

  alias Archethic.Reward.MemTables.RewardTokens
  alias Archethic.Reward.MemTablesLoader
  @unit_uco 100_000_000

  @doc """
  Get rewards amount for validation nodes
  """
  @spec validation_nodes_reward() :: pos_integer()
  def validation_nodes_reward do
    date = DateTime.utc_now()

    uco_usd_price =
      date
      |> OracleChain.get_uco_price()
      |> Keyword.get(:usd)

    trunc(50 / uco_usd_price / Calendar.ISO.days_in_month(date.year, date.month) * @unit_uco)
  end

  @doc """
  Create a transaction for minting new rewards

  ## Examples

    iex> %{
    ...>  type: :mint_rewards,
    ...>  data: %{
    ...>    content: "{\\n  \\"supply\\":2000000000,\\n  \\"type\\":\\"fungible\\",\\n  \\"name\\":\\"Mining UCO rewards\\",\\n  \\"symbol\\":\\"MUCO\\"\\n}\\n"
    ...>  }
    ...> } = Reward.new_rewards_mint(2_000_000_000)
  """
  @spec new_rewards_mint(amount :: non_neg_integer()) :: Transaction.t()
  def new_rewards_mint(amount) do
    data = %TransactionData{
      code: """
        condition inherit: [
          # We need to ensure the type stays consistent
          type: in?([mint_rewards, node_rewards]),
          content: true,
          token_transfers: true
        ]
      """,
      content: """
      {
        "supply":#{amount},
        "type":"fungible",
        "name":"Mining UCO rewards",
        "symbol":"MUCO"
      }
      """
    }

    Transaction.new(:mint_rewards, data)
  end

  @spec new_node_rewards() :: Transaction.t()
  def new_node_rewards() do
    data = %TransactionData{
      code: """
        condition inherit: [
          # We need to ensure the type stays consistent
          type: in?([mint_rewards, node_rewards]),
          content: true,
          token_transfers: true
        ]
      """,
      ledger: %Ledger{
        token: %TokenLedger{
          transfers: get_transfers()
        }
      }
    }

    Transaction.new(:node_rewards, data)
  end

  @doc """
  Determine if the local node is the initiator of the new rewards mint
  """
  @spec initiator?(binary()) :: boolean()
  def initiator?(address, index \\ 0) do
    %Node{first_public_key: initiator_key} =
      address
      |> Election.storage_nodes(P2P.authorized_and_available_nodes())
      |> Enum.at(index)

    initiator_key == Crypto.first_node_public_key()
  end

  @spec next_address() :: binary()
  def next_address do
    key_index = Crypto.number_of_network_pool_keys()
    next_public_key = Crypto.network_pool_public_key(key_index + 1)
    Crypto.derive_address(next_public_key)
  end

  @doc """
  Return the list of transfers to rewards the validation nodes
  """
  @spec get_transfers() :: reward_transfers :: list(Transfer.t())
  def get_transfers() do
    uco_amount = validation_nodes_reward()

    nodes =
      P2P.authorized_nodes()
      |> Enum.map(fn %Node{reward_address: reward_address} ->
        {reward_address, uco_amount}
      end)

    network_pool_balance =
      SharedSecrets.get_network_pool_address()
      |> Account.get_balance()
      |> Map.get(:token)
      |> Map.to_list()
      |> Enum.sort(fn {_, qty1}, {_, qty2} -> qty1 < qty2 end)

    do_get_transfers(nodes, network_pool_balance, [])
  end

  defp do_get_transfers([node | rest], network_pool_balance, acc) do
    {address, amount} = node

    {transfers, network_pool_balance} =
      get_node_transfers(address, network_pool_balance, amount, [])

    do_get_transfers(rest, network_pool_balance, Enum.concat(acc, transfers))
  end

  defp do_get_transfers([], _, acc), do: acc

  defp get_node_transfers(reward_address, [token | rest], amount, acc) when amount > 0 do
    {{token_address, token_id}, token_amount} = token

    if amount >= token_amount do
      transfer = %Transfer{
        amount: token_amount,
        to: reward_address,
        token: token_address,
        token_id: token_id
      }

      amount = amount - token_amount

      get_node_transfers(reward_address, rest, amount, [transfer | acc])
    else
      transfer = %Transfer{
        amount: amount,
        to: reward_address,
        token: token_address,
        token_id: token_id
      }

      token = {{token_address, token_id}, token_amount - amount}

      get_node_transfers(reward_address, [token | rest], 0, [transfer | acc])
    end
  end

  defp get_node_transfers(_, network_pool_balance, 0, acc), do: {acc, network_pool_balance}

  defp get_node_transfers(_, [], _, acc), do: {acc, []}

  @doc """
  Returns the last date of the rewards scheduling from the network pool
  """
  @spec last_scheduling_date() :: DateTime.t()
  defdelegate last_scheduling_date, to: Scheduler, as: :last_date

  def config_change(changed_conf) do
    changed_conf
    |> Keyword.get(Scheduler)
    |> Scheduler.config_change()
  end

  def reload_transactions() do
    MemTablesLoader.reload_memtables()
    :ok
  end

  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(tx = %Transaction{type: :mint_rewards}) do
    MemTablesLoader.load_transaction(tx)
  end

  def load_transaction(_tx = %Transaction{type: _}) do
    :ok
  end

  def is_reward_token?(token_address) when is_binary(token_address) do
    RewardTokens.exists?(token_address)
  end
end
