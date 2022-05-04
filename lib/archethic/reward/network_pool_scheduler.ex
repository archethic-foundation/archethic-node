defmodule Archethic.Reward.NetworkPoolScheduler do
  @moduledoc false

  use GenServer

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Reward

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  alias Archethic.Utils

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def start_scheduling do
    GenServer.cast(__MODULE__, :start_scheduling)
  end

  @doc """
  Get the last node rewards scheduling date
  """
  @spec last_date() :: DateTime.t()
  def last_date do
    GenServer.call(__MODULE__, :last_date)
  end

  def init(args) do
    interval = Keyword.fetch!(args, :interval)
    {:ok, %{interval: interval}, :hibernate}
  end

  def handle_info(
        {:node_update, %Node{authorized?: true, first_public_key: first_public_key}},
        state = %{interval: interval}
      ) do
    if Crypto.first_node_public_key() == first_public_key do
      case Map.get(state, :timer) do
        nil ->
          timer = schedule(interval)
          Logger.info("Start the network pool reward scheduler")
          {:noreply, Map.put(state, :timer, timer), :hibernate}

        _ ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info(
        {:node_update, %Node{authorized?: false, first_public_key: first_public_key}},
        state = %{timer: timer}
      ) do
    if Crypto.first_node_public_key() == first_public_key do
      Process.cancel_timer(timer)
      {:noreply, Map.delete(state, :timer)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:node_update, _}, state), do: {:noreply, state}

  def handle_info(:send_rewards, state = %{interval: interval}) do
    timer = schedule(interval)

    if sender?() do
      interval
      |> get_last_date
      |> Reward.get_transfers_for_in_need_validation_nodes()
      |> send_rewards()
    end

    {:noreply, Map.put(state, :timer, timer), :hibernate}
  end

  def handle_call(:last_date, _, state = %{interval: interval}) do
    {:reply, get_last_date(interval), state}
  end

  def handle_cast({:new_conf, conf}, state) do
    case Keyword.get(conf, :interval) do
      nil ->
        {:noreply, state}

      new_interval ->
        {:noreply, Map.put(state, :interval, new_interval)}
    end
  end

  defp get_last_date(interval) do
    cron_expression = CronParser.parse!(interval, true)

    case DateTime.utc_now() do
      %DateTime{microsecond: {0, 0}} ->
        cron_expression
        |> CronScheduler.get_next_run_dates(DateTime.utc_now() |> DateTime.to_naive())
        |> Enum.at(1)
        |> DateTime.from_naive!("Etc/UTC")

      _ ->
        cron_expression
        |> CronScheduler.get_previous_run_date!(DateTime.utc_now() |> DateTime.to_naive())
        |> DateTime.from_naive!("Etc/UTC")
    end
  end

  defp sender? do
    next_transaction_index = Crypto.number_of_network_pool_keys() + 1
    node_public_key = Crypto.last_node_public_key()

    with true <- P2P.authorized_node?(),
         next_address <-
           Crypto.node_shared_secrets_public_key(next_transaction_index) |> Crypto.hash(),
         [%Node{last_public_key: ^node_public_key} | _] <-
           Election.storage_nodes(next_address, P2P.authorized_nodes()) do
      true
    else
      _ ->
        false
    end
  end

  defp send_rewards([]), do: :ok

  defp send_rewards(transfers) do
    Logger.debug("Sending node reward transaction")

    Transaction.new(:node_rewards, %TransactionData{
      code: """
      condition inherit: [ 
         # We need to ensure the transaction type keep consistent
         # So we can apply specific rules during the transaction verification
         type: node_rewards
      ]
      """,
      ledger: %Ledger{
        uco: %UCOLedger{
          transfers: transfers
        }
      }
    })
    |> Archethic.send_new_transaction()
  end

  defp schedule(interval) do
    Process.send_after(self(), :send_rewards, Utils.time_offset(interval) * 1000)
  end

  def config_change(nil), do: :ok

  def config_change(conf) do
    GenServer.cast(__MODULE__, {:new_conf, conf})
  end
end
