defmodule Uniris.Reward.WithdrawScheduler do
  @moduledoc false

  use GenServer

  alias Uniris.Account

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.UCOLedger
  alias Uniris.TransactionChain.TransactionData.UCOLedger.Transfer

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
        :ok

      timer ->
        Process.cancel_timer(timer)
    end

    timer = schedule(interval)

    Logger.info("Start the node rewards withdraw scheduler")

    {:noreply, Map.put(state, :timer, timer), :hibernate}
  end

  def handle_info(:withdraw_rewards, state = %{interval: interval}) do
    timer = schedule(interval)

    send_withdraw_transaction()

    {:noreply, Map.put(state, :timer, timer), :hibernate}
  end

  defp send_withdraw_transaction do
    network_pool_address = TransactionChain.get_last_address_by_type(:node_rewards)

    %Node{reward_address: reward_address, last_address: last_address} = P2P.get_node_info()

    reward_amount =
      last_address
      |> Account.get_unspent_outputs()
      |> Enum.reduce(0.0, &(&1.amount + &2))

    tx_fee =
      Transaction.fee(
        Transaction.new(:transfer, %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: transfers(reward_amount, reward_address, network_pool_address)
            }
          }
        })
      )

    if reward_amount - tx_fee > 0 do
      Logger.debug("Withdraw #{reward_amount} to #{Base.encode16(reward_address)}")

      tx_data = %TransactionData{
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers: transfers(reward_amount - tx_fee, reward_address, network_pool_address)
          }
        }
      }

      tx = Transaction.new(:transfer, tx_data)

      Uniris.send_new_transaction(tx)
    end
  end

  defp transfers(amount, reward_address, network_pool_address) do
    [
      %Transfer{to: reward_address, amount: Float.floor(amount * 0.90, 15)},
      %Transfer{to: network_pool_address, amount: Float.floor(amount * 0.10, 15)}
    ]
  end

  defp schedule(interval) do
    Process.send_after(self(), :withdraw_rewards, Utils.time_offset(interval) * 1000)
  end
end
