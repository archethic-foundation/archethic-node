defmodule Uniris.Reward.NetworkPoolScheduler do
  @moduledoc false

  use GenServer

  alias Uniris.Crypto

  alias Uniris.Election

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.Reward

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.UCOLedger

  alias Uniris.Utils

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def start_scheduling do
    GenServer.cast(__MODULE__, :start_scheduling)
  end

  def init(args) do
    interval = Keyword.fetch!(args, :interval)
    {:ok, %{interval: interval}, :hibernate}
  end

  def handle_cast(:start_scheduling, state = %{interval: interval}) do
    case Map.get(state, :timer) do
      nil ->
        timer = schedule(interval)
        Logger.info("Start the network pool reward scheduler")
        {:noreply, Map.put(state, :timer, timer), :hibernate}

      _timer ->
        {:noreply, state}
    end
  end

  def handle_info(:send_rewards, state = %{interval: interval}) do
    timer = schedule(interval)

    if sender?() do
      send_rewards()
    end

    {:noreply, Map.put(state, :timer, timer), :hibernate}
  end

  defp sender? do
    next_transaction_index = Crypto.number_of_network_pool_keys() + 1
    node_public_key = Crypto.node_public_key()

    with %Node{authorized?: true} <- P2P.get_node_info(),
         next_address <-
           Crypto.node_shared_secrets_public_key(next_transaction_index) |> Crypto.hash(),
         [%Node{last_public_key: ^node_public_key} | _] <-
           Election.storage_nodes(next_address, P2P.list_nodes(authorized?: true)) do
      true
    else
      _ ->
        false
    end
  end

  defp send_rewards do
    case Reward.get_transfers_for_in_need_validation_nodes() do
      [] ->
        :ok

      transfers ->
        Transaction.new(:node_rewards, %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: transfers
            }
          }
        })
        |> Uniris.send_new_transaction()
    end
  end

  defp schedule(interval) do
    Process.send_after(self(), :send_rewards, Utils.time_offset(interval) * 1000)
  end
end
