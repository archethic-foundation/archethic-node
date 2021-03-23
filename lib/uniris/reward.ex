defmodule Uniris.Reward do
  @moduledoc """
  Module which handles the rewards and transfer scheduling
  """

  alias Uniris.OracleChain

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias __MODULE__.NetworkPoolScheduler
  alias __MODULE__.WithdrawScheduler

  alias Uniris.TransactionChain.TransactionData.UCOLedger.Transfer

  @doc """
  Start the network pool reward scheduling
  """
  @spec start_network_pool_scheduling() :: :ok
  defdelegate start_network_pool_scheduling, to: NetworkPoolScheduler, as: :start_scheduling

  @doc """
  Start the node reward scheduling
  """
  @spec start_node_withdraw_scheduling() :: :ok
  defdelegate start_node_withdraw_scheduling, to: WithdrawScheduler, as: :start_scheduling

  @doc """
  Get the minimum rewards for validation nodes
  """
  @spec min_validation_nodes_reward() :: float()
  def min_validation_nodes_reward do
    uco_eur_price = OracleChain.get_uco_price() |> Keyword.get(:eur)
    uco_eur_price * 50
  end

  @doc """
  Return the list of transaction for the validation nodes which receive less than the minimum validation node reward
  """
  @spec get_transfers_for_in_need_validation_nodes() :: list(Transfer.t())
  def get_transfers_for_in_need_validation_nodes do
    min_validation_nodes_reward = min_validation_nodes_reward()

    Enum.map(P2P.list_nodes(authorized?: true), fn node = %Node{last_address: last_address} ->
      {:ok, %UnspentOutputList{unspent_outputs: unspent_outputs}} =
        last_address
        |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
        |> P2P.reply_first(%GetUnspentOutputs{address: last_address})

      {node, Enum.reduce(unspent_outputs, 0.0, &(&1.amount + &2))}
    end)
    |> Enum.filter(fn {_, balance} -> balance < min_validation_nodes_reward end)
    |> Enum.map(fn {%Node{reward_address: address}, amount} ->
      %Transfer{to: address, amount: min_validation_nodes_reward - amount}
    end)
  end
end
