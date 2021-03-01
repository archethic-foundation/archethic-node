defmodule Uniris.OracleChain.Scheduler do
  @moduledoc """
  Manage the scheduling of the oracle transactions
  """

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  alias Uniris.Crypto

  alias Uniris.Election

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.OracleChain.Services

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

    {:ok,
     %{
       polling_interval: polling_interval,
       summary_interval: summary_interval
     }}
  end

  def handle_cast(
        :start_scheduling,
        state = %{polling_interval: polling_interval, summary_interval: summary_interval}
      ) do
    cancel_scheduler(:polling_scheduler, state)
    cancel_scheduler(:summary_scheduler, state)

    polling_scheduler = schedule_new_polling(polling_interval)
    summary_scheduler = schedule_new_summary(summary_interval)

    new_state =
      state
      |> Map.put(:polling_scheduler, polling_scheduler)
      |> Map.put(:summary_scheduler, summary_scheduler)

    Logger.info("Start the Oracle scheduler")

    {:noreply, new_state}
  end

  defp cancel_scheduler(scheduler, state) do
    case Map.get(state, scheduler) do
      nil ->
        :ok

      timer ->
        Process.cancel_timer(timer)
    end
  end

  def handle_info(:poll, state = %{polling_interval: interval}) do
    schedule_new_polling(interval)

    date = DateTime.utc_now() |> Utils.truncate_datetime()

    if trigger_node?(date) do
      Logger.debug("Trigger oracle data fecthing")
      me = self()

      previous_date = Map.get(state, :last_poll_date) || get_previous_date(interval, date)
      Task.start(fn -> handle_new_polling(me, previous_date, date) end)
    end

    {:noreply, state, :hibernate}
  end

  def handle_info(:summary, state = %{summary_interval: interval, last_poll_date: last_poll_date}) do
    schedule_new_summary(interval)

    date = DateTime.utc_now() |> Utils.truncate_datetime()

    if trigger_node?(date) do
      last_summary_date = get_previous_date(interval, date)
      Task.start(fn -> handle_new_summary(last_summary_date, date, last_poll_date) end)
    end

    {:noreply, state, :hibernate}
  end

  def handle_info(:summary, state), do: {:noreply, state}

  def handle_info({:new_polling_date, date}, state) do
    {:noreply, Map.put(state, :last_poll_date, date)}
  end

  defp get_previous_date(interval, date = %DateTime{}) do
    interval
    |> CronParser.parse!(true)
    |> CronScheduler.get_previous_run_dates(DateTime.to_naive(date))
    |> Enum.at(1)
    |> DateTime.from_naive!("Etc/UTC")
  end

  defp schedule_new_polling(interval) do
    Process.send_after(self(), :poll, Utils.time_offset(interval) * 1000)
  end

  defp schedule_new_summary(interval) do
    Process.send_after(self(), :summary, Utils.time_offset(interval) * 1000)
  end

  defp trigger_node?(date = %DateTime{}) do
    {next_pub, _pv} = Crypto.derive_oracle_keypair(date)
    next_address = Crypto.hash(next_pub)

    node_public_key = Crypto.node_public_key(0)

    case Election.storage_nodes(next_address, P2P.list_nodes(availability: :global)) do
      [%Node{first_public_key: ^node_public_key} | _] ->
        true

      _ ->
        false
    end
  end

  defp handle_new_polling(pid, previous_date = %DateTime{}, date = %DateTime{}) do
    {prev_pub, prev_pv} = Crypto.derive_oracle_keypair(previous_date)
    {next_pub, _pv} = Crypto.derive_oracle_keypair(date)

    previous_content =
      case TransactionChain.get_transaction(Crypto.hash(prev_pub), data: [:content]) do
        {:ok, %Transaction{data: %TransactionData{content: previous_content}}} ->
          Jason.decode!(previous_content) |> Map.get("data")

        _ ->
          %{}
      end

    next_data = Services.fetch_new_data(previous_content)

    if map_size(next_data) > 0 do
      previous_hash = Crypto.hash(Jason.encode!(previous_content))

      Transaction.new(
        :oracle,
        %TransactionData{
          content:
            %{}
            |> Map.put("data", next_data)
            |> Map.put("previous_hash", Base.encode16(previous_hash))
            |> Map.put("last_updated_at", DateTime.to_unix(date))
            |> Jason.encode!()
        },
        prev_pv,
        prev_pub,
        next_pub
      )
      |> Uniris.send_new_transaction()

      send(pid, {:new_polling_date, date})
      Logger.debug("New data pushed to the oracle")
    else
      Logger.debug("No update for the oracle")
    end
  end

  defp handle_new_summary(last_summary_date, date, last_poll_date) do
    {prev_pub, prev_pv} = Crypto.derive_oracle_keypair(last_summary_date)

    previous_hash =
      case TransactionChain.get_transaction(Crypto.hash(prev_pub), data: [:content]) do
        {:ok, %Transaction{data: %TransactionData{content: content}}} ->
          Crypto.hash(content)

        _ ->
          ""
      end

    {last_poll_pub, _pv} = Crypto.derive_oracle_keypair(last_poll_date)

    aggregated_content =
      TransactionChain.get(Crypto.hash(last_poll_pub), data: [:content])
      |> Enum.map(fn %Transaction{data: %TransactionData{content: content}} ->
        map = Jason.decode!(content)

        data = Map.get(map, "data")
        last_updated_at = Map.get(map, "last_updated_at")
        {last_updated_at, data}
      end)
      |> Enum.into(%{})

    {next_pub, _} = Crypto.derive_oracle_keypair(date)

    Transaction.new(
      :oracle_summary,
      %TransactionData{
        content:
          %{}
          |> Map.put("data", aggregated_content)
          |> Map.put("previous_hash", Base.encode16(previous_hash))
          |> Jason.encode!()
      },
      prev_pv,
      prev_pub,
      next_pub
    )
    |> Uniris.send_new_transaction()
  end
end
