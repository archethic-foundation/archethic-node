defmodule ArchEthic.Reward do
  @moduledoc """
  Module which handles the rewards and transfer scheduling
  """

  alias ArchEthic.Election

  alias ArchEthic.OracleChain

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.GetUnspentOutputs
  alias ArchEthic.P2P.Message.TransactionList
  alias ArchEthic.P2P.Message.UnspentOutputList
  alias ArchEthic.P2P.Node

  alias __MODULE__.NetworkPoolScheduler

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer

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
  Return the list of transfers to rewards the validation nodes which receive less than the minimum validation node reward

  This will get and check all the unspent outputs after the last reward date and determine which were mining reward
  and compare it with the minimum of rewards for a validation node
  """
  @spec get_transfers_for_in_need_validation_nodes(last_reward_date :: DateTime.t()) ::
          reward_transfers :: list(Transfer.t())
  def get_transfers_for_in_need_validation_nodes(last_date = %DateTime{}) do
    min_validation_nodes_reward = min_validation_nodes_reward()

    Task.async_stream(P2P.authorized_nodes(), fn node = %Node{reward_address: reward_address} ->
      mining_rewards =
        reward_address
        |> get_transactions_after(last_date)
        |> Task.async_stream(&get_reward_unspent_outputs/1, timeout: 500, on_exit: :kill_task)
        |> Stream.filter(&match?({:ok, _}, &1))
        |> Enum.flat_map(& &1)

      {node, mining_rewards}
    end)
    |> Enum.filter(fn {_, balance} -> balance < min_validation_nodes_reward end)
    |> Enum.map(fn {%Node{reward_address: address}, amount} ->
      %Transfer{to: address, amount: min_validation_nodes_reward - amount}
    end)
  end

  defp get_transactions_after(address, date) do
    last_address = TransactionChain.resolve_last_address(address, DateTime.utc_now())

    last_address
    |> Election.chain_storage_nodes(P2P.available_nodes())
    |> P2P.nearest_nodes()
    |> get_transaction_chain_after(address, date)
  end

  defp get_transaction_chain_after([node | rest], address, date) do
    case P2P.send_message(node, %GetTransactionChain{address: address, after: date}) do
      {:ok, %TransactionList{transactions: transactions}} ->
        transactions

      {:error, _} ->
        get_transaction_chain_after(rest, address, date)
    end
  end

  defp get_reward_unspent_outputs(%Transaction{address: address}) do
    address
    |> Election.chain_storage_nodes(P2P.available_nodes())
    |> P2P.nearest_nodes()
    |> get_unspent_outputs(address)
    |> Enum.filter(&(&1.type == :reward))
  end

  defp get_unspent_outputs([node | rest], address) do
    case P2P.send_message(node, %GetUnspentOutputs{address: address}) do
      {:ok, %UnspentOutputList{unspent_outputs: unspent_outputs}} ->
        unspent_outputs

      {:error, _} ->
        get_unspent_outputs(rest, address)
    end
  end

  defp get_unspent_outputs([], _), do: {:error, :network_issue}

  def load_transaction(_), do: :ok

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
