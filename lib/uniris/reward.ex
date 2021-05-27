defmodule Uniris.Reward do
  @moduledoc """
  Module which handles the rewards and transfer scheduling
  """

  alias Uniris.Crypto

  alias Uniris.OracleChain

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias __MODULE__.NetworkPoolScheduler

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys
  alias Uniris.TransactionChain.TransactionData.UCOLedger.Transfer

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

    Task.async_stream(P2P.authorized_nodes(), fn node = %Node{reward_address: reward_address} ->
      {:ok, %UnspentOutputList{unspent_outputs: unspent_outputs}} =
        reward_address
        |> TransactionChain.resolve_last_address(DateTime.utc_now())
        |> Replication.chain_storage_nodes()
        |> P2P.reply_first(%GetUnspentOutputs{address: reward_address})

      mining_rewards =
        unspent_outputs
        |> Enum.filter(
          &(&1.type == :reward and DateTime.compare(&1.timestamp, DateTime.utc_now()) == :lt)
        )
        |> Enum.reduce(0.0, &(&1.amount + &2))

      {node, mining_rewards}
    end)
    |> Enum.filter(fn {_, balance} -> balance < min_validation_nodes_reward end)
    |> Enum.map(fn {%Node{reward_address: address}, amount} ->
      %Transfer{to: address, amount: min_validation_nodes_reward - amount}
    end)
  end

  def load_transaction(%Transaction{
        type: :node_shared_secrets,
        data: %TransactionData{keys: keys}
      }) do
    if Crypto.last_node_public_key() in Keys.list_authorized_keys(keys) do
      NetworkPoolScheduler.start_scheduling()
    end

    :ok
  end

  def load_transaction(_), do: :ok
end
