defmodule Archethic.Reward do
  @moduledoc """
  Module which handles the rewards and transfer scheduling
  """

  alias Archethic.Crypto

  alias Archethic.Account

  alias Archethic.OracleChain

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias __MODULE__.MemTables.RewardTokens
  alias __MODULE__.MemTablesLoader
  alias __MODULE__.Scheduler
  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain

  alias Archethic.TransactionChain.{
    Transaction,
    TransactionData,
    TransactionData.Ledger,
    TransactionData.TokenLedger,
    TransactionData.TokenLedger.Transfer
  }

  alias Archethic.Utils

  alias Crontab.CronExpression.Parser, as: CronParser

  require Logger

  @unit_uco 100_000_000
  @number_of_occurences_per_month_for_a_year Utils.number_of_possible_reward_occurences_per_month_for_a_year()

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

    number_of_reward_occurences_per_month = number_of_reward_occurences_per_month()

    trunc(50 / uco_usd_price / number_of_reward_occurences_per_month * @unit_uco)
  end

  defp number_of_reward_occurences_per_month() do
    datetime = NaiveDateTime.utc_now()

    key = Utils.get_key_from_date(datetime)

    Map.get(@number_of_occurences_per_month_for_a_year, key)
  end

  @doc """
  Create a transaction for minting new rewards

  ## Examples

    iex> %{
    ...>  type: :mint_rewards,
    ...>  data: %{
    ...>    content: "{\\n  \\"supply\\":2000000000,\\n  \\"type\\":\\"fungible\\",\\n  \\"name\\":\\"Mining UCO rewards\\",\\n  \\"symbol\\":\\"MUCO\\"\\n}\\n"
    ...>  }
    ...> } = Reward.new_rewards_mint(2_000_000_000, 1)
  """
  @spec new_rewards_mint(amount :: non_neg_integer(), index :: non_neg_integer()) ::
          Transaction.t()
  def new_rewards_mint(amount, index) do
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

    Transaction.new(:mint_rewards, data, index)
  end

  @spec new_node_rewards(non_neg_integer()) :: Transaction.t()
  def new_node_rewards(index) do
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

    Transaction.new(:node_rewards, data, index)
  end

  @spec next_address(non_neg_integer()) :: binary()
  def next_address(index) do
    (index + 1)
    |> Crypto.network_pool_public_key()
    |> Crypto.derive_address()
  end

  @doc """
  Return the list of transfers to rewards the validation nodes
  """
  @spec get_transfers() :: reward_transfers :: list(Transfer.t())
  def get_transfers() do
    uco_amount = validation_nodes_reward()

    nodes =
      P2P.authorized_and_available_nodes()
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
        token_address: token_address,
        token_id: token_id
      }

      amount = amount - token_amount

      get_node_transfers(reward_address, rest, amount, [transfer | acc])
    else
      transfer = %Transfer{
        amount: amount,
        to: reward_address,
        token_address: token_address,
        token_id: token_id
      }

      token = {{token_address, token_id}, token_amount - amount}

      get_node_transfers(reward_address, [token | rest], 0, [transfer | acc])
    end
  end

  defp get_node_transfers(_, network_pool_balance, 0, acc), do: {acc, network_pool_balance}

  defp get_node_transfers(_, [], _, acc), do: {acc, []}

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

  @doc """
  Return the last scheduling date
  """
  @spec get_last_scheduling_date(DateTime.t()) :: DateTime.t()
  def get_last_scheduling_date(date_from = %DateTime{} \\ DateTime.utc_now()) do
    :archethic
    |> Application.get_env(Scheduler)
    |> Keyword.fetch!(:interval)
    |> CronParser.parse!(true)
    |> Utils.previous_date(date_from)
  end

  @key :reward_gen_addr
  @spec persist_gen_addr() :: :ok
  def persist_gen_addr() do
    case TransactionChain.list_addresses_by_type(:mint_rewards)
         |> Stream.take(1)
         |> Enum.at(0) do
      nil ->
        :error

      addr ->
        gen_addr = TransactionChain.get_genesis_address(addr)

        :persistent_term.put(@key, gen_addr)
        :ok
    end
  end

  @spec genesis_address() :: binary() | nil
  def genesis_address() do
    :persistent_term.get(@key, nil)
  end

  defmodule Gamification do
    @gamification_wallet 34400000

    def list_of_active_patches(node_list, current_date) do
      Enum.filter(node_list, fn node ->
        date_of_joining = elem(node, 3)
        average_availability = elem(node, 1)

        days_since_joining = Date.diff(current_date, date_of_joining) |> elem(0)
        days_since_joining >= 45 and average_availability >= 0.75
      end)
    end

    def organize_by_patch_id(node_list) do
      sorted_node_list = Enum.sort(node_list, &elem(&1, 2))
      Enum.reduce(sorted_node_list, [], fn node, acc ->
        patch_id = elem(node, 2)

        case acc do
          [] -> [[node]]
          [current_group | rest] ->
            current_patch_id = elem(hd(current_group), 2)
            if current_patch_id != patch_id do
              [[node] | acc]
            else
              [[node | current_group] | rest]
            end
        end
      end)
      |> Enum.reverse()
    end

    def gamification_reward(gamification_node_list, current_date) do
      reward_list = []

      earliest_date_of_joining = Enum.min_by(gamification_node_list, &elem(&1, 3)) |> elem(3)
      gamification_reward_duration = 10  # The gamification reward is designed for 10 years
      years = Enum.to_list(1..gamification_reward_duration)
      rewards_per_year_in_percentage = Enum.map(years, fn year -> 0.1 * year * year end)

      Enum.each(gamification_node_list, fn node ->
        node_id = elem(node, 0)
        patch_id = elem(node, 2)
        date_of_joining = elem(node, 3)
        average_availability = elem(node, 1)

        days_since_joining = Date.diff(current_date, earliest_date_of_joining) |> elem(0)
        if rem(days_since_joining, 365) == 0 do
          number_of_years = div(days_since_joining, 365)
          gamification_reward_patch = (@gamification_wallet / (50 * Enum.sum(rewards_per_year_in_percentage))) * (0.1 * number_of_years * number_of_years)
          gamification_reward_unit = average_availability * Date.diff(current_date, date_of_joining) |> elem(0)
          node_reward = gamification_reward_unit * average_availability * Date.diff(current_date, date_of_joining) |> elem(0)
          reward_list = [[node_id, patch_id, node_reward] | reward_list]
        end
      end)

      reward_list
    end
  end

end
