defmodule Archethic.Reward do
  @moduledoc """
  Module which handles the rewards and transfer scheduling
  """

  alias Archethic.OracleChain

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias __MODULE__.RewardScheduler

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer

  @unit_uco 100_000_000

  @doc """
  Get the minimum rewards for validation nodes
  """
  @spec min_validation_nodes_reward() :: pos_integer()
  def min_validation_nodes_reward do
    uco_eur_price =
      DateTime.utc_now()
      |> OracleChain.get_uco_price()
      |> Keyword.get(:eur)

    trunc(uco_eur_price * 50) * @unit_uco
  end

  @doc """
  Create a transaction for minting new rewards

  ## Examples

    iex> case Reward.new_rewards_mint(2_000_000_000) do
    ...>  %{
    ...>    type: :mint_rewards,
    ...>    data: %{
    ...>      content: "{\\n  \\"supply\\":2000000000,\\n  \\"type\\":\\"fungible\\",\\n  \\"name\\":\\"Mining UCO rewards\\",\\n  \\"symbol\\":\\"MUCO\\"\\n}\\n"
    ...>    }
    ...>  } ->
    ...>    :ok
    ...>  _ ->
    ...>    :error
    ...> end
    :ok
  """
  @spec new_rewards_mint(amount :: non_neg_integer()) :: Transaction.t()
  def new_rewards_mint(amount) do
    data = %TransactionData{
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

  @doc """
  Determine if the local node is the initiator of the new rewards mint
  """
  @spec initiator?() :: boolean()
  def initiator? do
    %Node{first_public_key: initiator_key} =
      next_address()
      |> Election.storage_nodes(P2P.authorized_and_available_nodes())
      |> List.first()

    initiator_key == Crypto.first_node_public_key()
  end

  defp next_address do
    key_index = Crypto.number_of_network_pool_keys()
    next_public_key = Crypto.network_pool_public_key(key_index + 1)
    Crypto.derive_address(next_public_key)
  end

  @doc """
  Return the list of transfers to rewards the validation nodes for a specific date
  """
  @spec get_transfers(last_reward_date :: DateTime.t()) :: reward_transfers :: list(Transfer.t())
  def get_transfers(_last_date = %DateTime{}) do
    # TODO
    []
  end

  @doc """
  Returns the last date of the rewards scheduling from the network pool
  """
  @spec last_scheduling_date() :: DateTime.t()
  defdelegate last_scheduling_date, to: RewardScheduler, as: :last_date

  def config_change(changed_conf) do
    changed_conf
    |> Keyword.get(RewardScheduler)
    |> RewardScheduler.config_change()
  end
end
