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

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  use GenStateMachine, callback_mode: [:handle_event_function]

  require Logger

  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenStateMachine.start_link(__MODULE__, args, opts)
  end

  def init(args) do
    polling_interval = Keyword.fetch!(args, :polling_interval)
    summary_interval = Keyword.fetch!(args, :summary_interval)

    PubSub.register_to_node_update()

    {:ok, :idle,
     %{
       polling_interval: polling_interval,
       polling_date: next_date(polling_interval),
       summary_interval: summary_interval,
       summary_date: next_date(summary_interval)
     }}
  end

  def handle_event(
        :info,
        :poll,
        :idle,
        data = %{
          polling_date: polling_date,
          summary_date: summary_date
        }
      ) do
    if DateTime.diff(polling_date, summary_date, :second) == 0 do
      {:next_state, :summary, data,
       [
         {:next_event, :internal, :aggregate},
         {:next_event, :internal, :update_summary_date},
         {:next_event, :internal, :fetch_data},
         {:next_event, :internal, :update_polling_date}
       ]}
    else
      {:next_state, :polling, data,
       [
         {:next_event, :internal, :fetch_data},
         {:next_event, :internal, :update_polling_date}
       ]}
    end
  end

  def handle_event(
        :internal,
        :fetch_data,
        :polling,
        data = %{
          polling_date: polling_date,
          summary_date: summary_date
        }
      ) do
    if trigger_node?(polling_date) do
      chain_size = chain_size(summary_date)

      {prev_pub, _} = Crypto.derive_oracle_keypair(summary_date, chain_size)

      new_oracle_data =
        prev_pub
        |> Crypto.hash()
        |> get_oracle_data()
        |> Services.fetch_new_data()

      if Enum.empty?(new_oracle_data) do
        Logger.debug("Oracle transaction skipped - no new data")
        {:next_state, :idle, data}
      else
        send_polling_transaction(new_oracle_data, chain_size, summary_date)
        {:keep_state, data}
      end
    else
      Logger.debug("Oracle transaction skipped - not the trigger node")
      {:next_state, :idle, data}
    end
  end

  def handle_event(
        :internal,
        :aggregate,
        :summary,
        data = %{summary_date: summary_date}
      ) do
    if trigger_node?(summary_date) do
      Logger.debug("Oracle transaction summary sending")

      send_summary_transaction(summary_date)
      {:keep_state, data}

      {:next_state, :polling, data}
    else
      Logger.debug("Oracle summary skipped - not the trigger node")

      {:next_state, :polling, data}
    end
  end

  def handle_event(
        :internal,
        :update_polling_date,
        _state,
        data = %{polling_date: polling_date, polling_interval: polling_interval}
      ) do
    next_polling_date = next_date(polling_interval, polling_date, true)

    new_data =
      data
      |> Map.put(:polling_date, next_polling_date)
      |> Map.put(:polling_timer, schedule_new_polling(next_polling_date))

    {:next_state, :idle, new_data}
  end

  def handle_event(
        :internal,
        :update_summary_date,
        _state,
        data = %{summary_date: summary_date, summary_interval: summary_interval}
      ) do
    next_summary_date = next_date(summary_interval, summary_date, true)
    Logger.info("Next Oracle Summary at #{DateTime.to_string(next_summary_date)}")

    new_data =
      data
      |> Map.put(:summary_date, next_summary_date)

    {:next_state, :polling, new_data}
  end

  def handle_event(
        :info,
        {:node_update, %Node{authorized?: true, first_public_key: first_public_key}},
        _state,
        data = %{polling_interval: polling_interval, summary_interval: summary_interval}
      ) do
    with ^first_public_key <- Crypto.first_node_public_key(),
         nil <- Map.get(data, :polling_timer) do
      next_polling_date = next_date(polling_interval)
      polling_timer = schedule_new_polling(next_polling_date)

      new_data =
        data
        |> Map.put(:polling_timer, polling_timer)
        |> Map.put(:summary_date, next_date(summary_interval))
        |> Map.put(:polling_date, next_polling_date)

      Logger.info("Start the Oracle scheduler")
      {:keep_state, new_data}
    else
      _ ->
        :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:node_update, %Node{authorized?: false, first_public_key: first_public_key}},
        _state,
        data = %{polling_timer: polling_timer}
      ) do
    if first_public_key == Crypto.first_node_public_key() do
      Process.cancel_timer(polling_timer)

      new_data =
        data
        |> Map.delete(:polling_timer)

      {:keep_state, new_data}
    else
      :keep_state_and_data
    end
  end

  def handle_event(:info, {:node_update, %Node{authorized?: false}}, _state, _data),
    do: :keep_state_and_data

  def handle_event(
        :cast,
        {:new_conf, conf},
        _,
        data = %{
          polling_interval: old_polling_interval,
          summary_interval: old_summary_interval
        }
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

    new_data =
      data
      |> Map.put(:polling_interval, polling_interval)
      |> Map.put(:summary_interval, summary_interval)

    {:keep_state, new_data}
  end

  def handle_event(
        {:call, from},
        :summary_interval,
        _state,
        _data = %{summary_interval: summary_interval}
      ) do
    {:keep_state_and_data, {:reply, from, summary_interval}}
  end

  defp schedule_new_polling(polling_date) do
    Logger.info("Next oracle polling at #{DateTime.to_string(polling_date)}")

    Process.send_after(
      self(),
      :poll,
      DateTime.diff(polling_date, DateTime.utc_now(), :millisecond)
    )
  end

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

  defp send_polling_transaction(oracle_data, chain_size, summary_date) do
    {prev_pub, prev_pv} = Crypto.derive_oracle_keypair(summary_date, chain_size)

    {next_pub, _} = Crypto.derive_oracle_keypair(summary_date, chain_size + 1)

    tx =
      Transaction.new_with_keys(
        :oracle,
        %TransactionData{
          content: Jason.encode!(oracle_data),
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

    Task.start(fn -> ArchEthic.send_new_transaction(tx) end)

    Logger.debug("New data pushed to the oracle",
      transaction_address: Base.encode16(tx.address),
      transaction_type: :oracle
    )
  end

  defp send_summary_transaction(summary_date) do
    oracle_chain =
      summary_date
      |> Crypto.derive_oracle_address(0)
      |> TransactionChain.get_last_address()
      |> TransactionChain.get(data: [:content], validation_stamp: [:timestamp])

    chain_size = Enum.count(oracle_chain)

    {prev_pub, prev_pv} = Crypto.derive_oracle_keypair(summary_date, chain_size)
    {next_pub, _} = Crypto.derive_oracle_keypair(summary_date, chain_size + 1)

    aggregated_content =
      %Summary{transactions: oracle_chain}
      |> Summary.aggregate()
      |> Summary.aggregated_to_json()

    tx =
      Transaction.new_with_keys(
        :oracle_summary,
        %TransactionData{
          code: """
            # We stop the inheritance of transaction by ensuring no other
            # summary transaction will continue on this chain
            condition inherit: [ content: "" ]
          """,
          content: aggregated_content
        },
        prev_pv,
        prev_pub,
        next_pub
      )

    Logger.debug(
      "Sending oracle summary transaction - aggregation: #{inspect(aggregated_content)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: :oracle_summary
    )

    Task.start(fn -> ArchEthic.send_new_transaction(tx) end)
  end

  defp chain_size(summary_date = %DateTime{}) do
    summary_date
    |> Crypto.derive_oracle_address(0)
    |> TransactionChain.get_last_address()
    |> TransactionChain.size()
  end

  defp get_oracle_data(address) do
    case TransactionChain.get_transaction(address, data: [:content]) do
      {:ok, %Transaction{data: %TransactionData{content: previous_content}}} ->
        Jason.decode!(previous_content)

      _ ->
        %{}
    end
  end

  defp next_date(interval, date \\ DateTime.utc_now(), force? \\ false) do
    case date do
      %DateTime{microsecond: {0, 0}} ->
        do_next_date(interval, date, true)

      _ ->
        do_next_date(interval, date, force?)
    end
  end

  defp do_next_date(interval, date = %DateTime{}, false) do
    interval
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_date!(DateTime.to_naive(date))
    |> DateTime.from_naive!("Etc/UTC")
  end

  defp do_next_date(interval, date = %DateTime{}, true) do
    interval
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_dates(DateTime.to_naive(date))
    |> Enum.at(1)
    |> DateTime.from_naive!("Etc/UTC")
  end

  def config_change(nil), do: :ok

  def config_change(conf) do
    GenStateMachine.cast(__MODULE__, {:new_conf, conf})
  end

  @doc """
  Retrieve the summary interval
  """
  @spec get_summary_interval :: binary()
  def get_summary_interval do
    GenStateMachine.call(__MODULE__, :summary_interval)
  end
end
