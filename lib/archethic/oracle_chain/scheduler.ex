defmodule ArchEthic.OracleChain.Scheduler do
  @moduledoc """
  Manage the scheduling of the oracle transactions
  """

  alias ArchEthic.Crypto

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias ArchEthic.PubSub

  alias ArchEthic.OracleChain.Services
  alias ArchEthic.OracleChain.Summary

  alias ArchEthic.TaskSupervisor

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData

  alias ArchEthic.Utils

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  use GenServer
  require Logger

  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
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
    with ^first_public_key <- Crypto.first_node_public_key(),
         nil <- Map.get(state, :polling_timer),
         nil <- Map.get(state, :summary_timer) do
      polling_timer = schedule_new_polling(polling_interval)
      summary_timer = schedule_new_summary(summary_interval)

      new_state =
        state
        |> Map.put(:polling_timer, polling_timer)
        |> Map.put(:summary_timer, summary_timer)

      Logger.info("Start the Oracle scheduler")
      {:noreply, new_state}
    else
      _ ->
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
        state = %{polling_interval: polling_interval, summary_interval: summary_interval}
      ) do
    timer = schedule_new_polling(polling_interval)
    date = DateTime.utc_now() |> DateTime.truncate(:second)

    if trigger_node?(date) do
      Logger.debug("Trigger oracle data fetching")

      Task.Supervisor.start_child(TaskSupervisor, fn ->
        summary_date = next_date(summary_interval)
        handle_polling(summary_date)
      end)

      {:noreply, Map.put(state, :polling_timer, timer)}
    else
      {:noreply, Map.put(state, :polling_timer, timer)}
    end
  end

  def handle_info(
        :summary,
        state = %{
          summary_interval: interval
        }
      ) do
    timer = schedule_new_summary(interval)

    date = DateTime.utc_now() |> DateTime.truncate(:second)

    # Because the time to schedule the transaction can variate in milliseconds,
    # a node could have stored an OracleSummary transaction but still
    # receiving a message to create a new summary transaction.
    # And this would be valid because the second didn't finished yet.
    # So to prevent an new oracle summary, we are fetching the last transaction on the chain.
    # If it's not a oracle_summary, then we can propose the summary transaction
    with true <- last_transaction_not_summary?(date),
         true <- trigger_node?(date) do
      Task.Supervisor.start_child(TaskSupervisor, fn ->
        handle_new_summary(date)
      end)
    end

    new_state =
      state
      |> Map.put(:summary_timer, timer)

    {:noreply, new_state, :hibernate}
  end

  def handle_info(:summary, state), do: {:noreply, state}

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

  def handle_call(:summary_interval, _from, state = %{summary_interval: summary_interval}) do
    {:reply, summary_interval, state}
  end

  defp schedule_new_polling(interval) do
    seconds = Utils.time_offset(interval)
    Logger.info("Next oracle polling in #{seconds} seconds")
    Process.send_after(self(), :poll, seconds * 1000)
  end

  defp schedule_new_summary(interval) do
    seconds = Utils.time_offset(interval)
    Logger.info("Next oracle summary in #{seconds} seconds")
    Process.send_after(self(), :summary, seconds * 1000)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp trigger_node?(summary_date = %DateTime{}) do
    chain_size = chain_size(summary_date)

    storage_nodes =
      summary_date
      |> Crypto.derive_oracle_address(chain_size)
      |> Election.storage_nodes(P2P.authorized_nodes())

    node_public_key = Crypto.first_node_public_key()

    case storage_nodes do
      [%Node{first_public_key: ^node_public_key} | _] ->
        true

      _ ->
        false
    end
  end

  defp chain_size(summary_date = %DateTime{}) do
    summary_date
    |> Crypto.derive_oracle_address(0)
    |> TransactionChain.get_last_address()
    |> TransactionChain.size()
  end

  defp last_transaction_not_summary?(date = %DateTime{}) do
    last_tx_address =
      date
      |> Crypto.derive_oracle_address(0)
      |> TransactionChain.get_last_address()

    case TransactionChain.get_transaction(last_tx_address, [:type]) do
      {:ok, %Transaction{type: :oracle_summary}} ->
        false

      _ ->
        true
    end
  end

  defp get_oracle_data(address) do
    case TransactionChain.get_transaction(address, data: [:content]) do
      {:ok, %Transaction{data: %TransactionData{content: previous_content}}} ->
        Jason.decode!(previous_content)

      _ ->
        %{}
    end
  end

  defp handle_polling(summary_date = %DateTime{}) do
    chain_size = chain_size(summary_date)

    {prev_pub, prev_pv} = Crypto.derive_oracle_keypair(summary_date, chain_size)

    next_data =
      prev_pub
      |> Crypto.hash()
      |> get_oracle_data()
      |> Services.fetch_new_data()

    if Enum.empty?(next_data) do
      Logger.debug("Oracle transaction skipped - no new data")
    else
      Logger.debug("Oracle transaction sending - new data")

      {next_pub, _} = Crypto.derive_oracle_keypair(summary_date, chain_size + 1)

      Transaction.new_with_keys(
        :oracle,
        %TransactionData{
          content: Jason.encode!(next_data),
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
      |> ArchEthic.send_new_transaction()

      Logger.debug("New data pushed to the oracle")
    end
  end

  defp handle_new_summary(summary_date = %DateTime{}) do
    oracle_chain =
      summary_date
      |> Crypto.derive_oracle_address(0)
      |> TransactionChain.get_last_address()
      |> TransactionChain.get(data: [:content], validation_stamp: [:timestamp])

    chain_size = Enum.count(oracle_chain)

    {prev_pub, prev_pv} = Crypto.derive_oracle_keypair(summary_date, chain_size)
    {next_pub, _} = Crypto.derive_oracle_keypair(summary_date, chain_size + 1)

    Transaction.new_with_keys(
      :oracle_summary,
      %TransactionData{
        code: """
          # We stop the inheritance of transaction by ensuring no other
          # summary transaction will continue on this chain
          condition inherit: [ content: "" ]
        """,
        content:
          %Summary{transactions: oracle_chain}
          |> Summary.aggregate()
          |> Summary.aggregated_to_json()
      },
      prev_pv,
      prev_pub,
      next_pub
    )
    |> ArchEthic.send_new_transaction()
  end

  defp next_date(interval, date \\ DateTime.utc_now())

  defp next_date(interval, date = %DateTime{microsecond: {0, 0}}) do
    interval
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_dates(DateTime.to_naive(date))
    |> Enum.at(1)
    |> DateTime.from_naive!("Etc/UTC")
  end

  defp next_date(interval, date = %DateTime{}) do
    interval
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_date!(DateTime.to_naive(date))
    |> DateTime.from_naive!("Etc/UTC")
  end

  def config_change(nil), do: :ok

  def config_change(conf) do
    GenServer.cast(__MODULE__, {:new_conf, conf})
  end

  @doc """
  Retrieve the summary interval
  """
  @spec get_summary_interval :: binary()
  def get_summary_interval do
    GenServer.call(__MODULE__, :summary_interval)
  end
end
