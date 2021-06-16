defmodule Uniris.OracleChain.Scheduler do
  @moduledoc """
  Manage the scheduling of the oracle transactions
  """

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  alias Uniris.Crypto

  alias Uniris.P2P.Node

  alias Uniris.PubSub

  alias Uniris.OracleChain.Services
  alias Uniris.OracleChain.Summary

  alias Uniris.Replication

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  alias Uniris.Utils

  use GenServer
  require Logger

  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  def start_scheduling do
    GenServer.cast(__MODULE__, :start_scheduling)
  end

  def init(args) do
    polling_interval = Keyword.fetch!(args, :polling_interval)
    summary_interval = Keyword.fetch!(args, :summary_interval)

    PubSub.register_to_node_update()

    {:ok,
     %{
       polling_interval: polling_interval,
       summary_interval: summary_interval
     }}
  end

  def handle_info(
        {:node_update, %Node{authorized?: true, first_public_key: first_public_key}},
        state = %{polling_interval: polling_interval, summary_interval: summary_interval}
      ) do
    if first_public_key == Crypto.first_node_public_key() do
      polling_timer = schedule_new_polling(polling_interval)
      summary_timer = schedule_new_summary(summary_interval)

      new_state =
        state
        |> Map.put(:polling_timer, polling_timer)
        |> Map.put(:summary_timer, summary_timer)

      Logger.info("Start the Oracle scheduler")
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        {:node_update, %Node{authorized?: false, first_public_key: first_public_key}},
        state
      ) do
    if first_public_key == Crypto.first_node_public_key() do
      Enum.each([:polling_timer, :summary_timer], &cancel_timer(Map.get(state, &1)))

      new_state =
        state
        |> Map.delete(:polling_timer)
        |> Map.delete(:summary_timer)

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        :poll,
        state = %{polling_interval: polling_interval}
      ) do
    timer = schedule_new_polling(polling_interval)

    date = DateTime.utc_now() |> Utils.truncate_datetime()

    if trigger_node?(date) do
      Logger.debug("Trigger oracle data fetching")
      me = self()

      previous_date = Map.get(state, :last_poll_date) || date

      handle_new_polling(
        me,
        previous_date,
        next_date(polling_interval)
      )
    end

    {:noreply, Map.put(state, :polling_timer, timer), :hibernate}
  end

  def handle_info(:summary, state = %{summary_interval: interval, last_poll_date: last_poll_date}) do
    timer = schedule_new_summary(interval)

    date = DateTime.utc_now() |> Utils.truncate_datetime()

    if trigger_node?(date) do
      handle_new_summary(last_poll_date, date)
    end

    me = self()

    Task.start(fn ->
      Process.sleep(3_000)
      send(me, :clean_polling_date)
    end)

    {:noreply, Map.put(state, :summary_timer, timer), :hibernate}
  end

  def handle_info(:summary, state), do: {:noreply, state}

  def handle_info({:new_polling_date, date}, state) do
    {:noreply, Map.put(state, :last_poll_date, date)}
  end

  def handle_info(:clean_polling_date, state) do
    {:noreply, Map.delete(state, :last_poll_date), :hibernate}
  end

  def handle_cast(
        {:new_conf, conf},
        state = %{polling_interval: old_polling_interval, summary_interval: old_summary_interval}
      ) do
    summary_interval =
      case Keyword.get(conf, :summary_interval) do
        nil ->
          old_summary_interval

        new_interval ->
          new_interval
      end

    polling_interval =
      case Keyword.get(conf, :polling_interval) do
        nil ->
          old_polling_interval

        new_interval ->
          new_interval
      end

    new_state =
      state
      |> Map.put(:polling_interval, polling_interval)
      |> Map.put(:summary_interval, summary_interval)

    {:noreply, new_state}
  end

  defp schedule_new_polling(interval) do
    Process.send_after(self(), :poll, Utils.time_offset(interval) * 1000)
  end

  defp schedule_new_summary(interval) do
    Process.send_after(self(), :summary, Utils.time_offset(interval) * 1000)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp trigger_node?(date = %DateTime{}) do
    {next_pub, _pv} = Crypto.derive_oracle_keypair(date)
    next_address = Crypto.hash(next_pub)

    node_public_key = Crypto.first_node_public_key()

    case Replication.chain_storage_nodes(next_address) do
      [%Node{first_public_key: ^node_public_key} | _] ->
        true

      _ ->
        false
    end
  end

  defp handle_new_polling(
         pid,
         previous_date = %DateTime{},
         date = %DateTime{}
       ) do
    {prev_pub, prev_pv} = Crypto.derive_oracle_keypair(previous_date)

    previous_data =
      case TransactionChain.get_transaction(Crypto.hash(prev_pub), data: [:content]) do
        {:ok, %Transaction{data: %TransactionData{content: previous_content}}} ->
          Jason.decode!(previous_content)

        _ ->
          %{}
      end

    new_data = Services.fetch_new_data(previous_data)

    if Enum.empty?(new_data) do
      Logger.debug("No update for the oracle")
    else
      {next_pub, _pv} = Crypto.derive_oracle_keypair(date)

      Transaction.new(
        :oracle,
        %TransactionData{
          content: Jason.encode!(new_data),
          code: ~S"""
          condition inherit: [
            # We need to ensure the type stays consistent
            # So we can apply specific rules during the transaction validation
            type: in?([oracle, oracle_summary]),

            # We discard the content and code verification
            content: true,
            
            # We ensure the code stay the same
            code: if type == oracle_summary do
              regex_match?("condition inherit: \\[[\\s].*content: \\\"\\\"[\\s].*]")
            else
              previous.code
            end
          ]
          """
        },
        prev_pv,
        prev_pub,
        next_pub
      )
      |> Uniris.send_new_transaction()

      send(pid, {:new_polling_date, date})
      Logger.debug("New data pushed to the oracle")
    end
  end

  defp handle_new_summary(last_poll_date, date) do
    oracle_chain =
      last_poll_date
      |> Crypto.derive_oracle_keypair()
      |> elem(0)
      |> Crypto.hash()
      |> TransactionChain.get(data: [:content], validation_stamp: [:timestamp])

    %Summary{transactions: oracle_chain, previous_date: last_poll_date, date: date}
    |> Summary.aggregate()
    |> Summary.to_transaction()
    |> Uniris.send_new_transaction()
  end

  defp next_date(interval) do
    interval
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_date!(DateTime.to_naive(DateTime.utc_now()))
    |> DateTime.from_naive!("Etc/UTC")
  end

  def config_change(nil), do: :ok

  def config_change(conf) do
    GenServer.cast(__MODULE__, {:new_conf, conf})
  end
end
