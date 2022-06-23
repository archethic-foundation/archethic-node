defmodule Archethic.Reward do
  @moduledoc """
  Module which handles the rewards and transfer scheduling
  """

  alias Archethic.OracleChain

  alias __MODULE__.NetworkPoolScheduler

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
  defdelegate last_scheduling_date, to: NetworkPoolScheduler, as: :last_date

  def config_change(changed_conf) do
    changed_conf
    |> Keyword.get(NetworkPoolScheduler)
    |> NetworkPoolScheduler.config_change()
  end
end
