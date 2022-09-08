defmodule Archethic.OracleChain.Scheduler do
  @moduledoc """
  Manage the scheduling of the oracle transactions
  """

  alias Archethic.Crypto
  alias Archethic.DB
  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.PubSub

  alias Archethic.OracleChain.Services
  alias Archethic.OracleChain.Summary

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.Utils.DetectNodeResponsiveness
  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  use GenStateMachine, callback_mode: [:handle_event_function]

  require Logger

  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenStateMachine.start_link(__MODULE__, args, opts)
  end

  @doc """
  Retrieve the summary interval
  """
  @spec get_summary_interval :: binary()
  def get_summary_interval do
    Application.get_env(:archethic, __MODULE__)
    |> Keyword.fetch!(:summary_interval)
  end

  def config_change(nil), do: :ok

  def config_change(conf) do
    GenStateMachine.cast(__MODULE__, {:new_conf, conf})
  end

  def init(args) do
    polling_interval = Keyword.fetch!(args, :polling_interval)
    summary_interval = Keyword.fetch!(args, :summary_interval)

    state_data =
      %{}
      |> Map.put(:polling_interval, polling_interval)
      |> Map.put(:summary_interval, summary_interval)

    case :persistent_term.get(:archethic_up, nil) do
      nil ->
        # node still bootstrapping , wait for it to finish Bootstrap
        Logger.info(" Oracle Scheduler: Waiting for Node to complete Bootstrap. ")

        PubSub.register_to_node_up()

        {:ok, :idle, state_data}

      # wait for node UP
      :up ->
        # when node is already bootstrapped, - handles scheduler crash
        {state, new_state_data, events} = start_scheduler(state_data)
        {:ok, state, new_state_data, events}
    end
  end

  def start_scheduler(state_data) do
    Logger.info("Oracle Scheduler: Starting... ")

    PubSub.register_to_node_update()

    case P2P.get_node_info(Crypto.first_node_public_key()) do
      # Schedule polling for authorized node
      # This case may happen in case of process restart after crash
      {:ok, %Node{authorized?: true, available?: true}} ->
        summary_date =
          next_date(
            Map.get(state_data, :summary_interval),
            DateTime.utc_now() |> DateTime.truncate(:second)
          )

        PubSub.register_to_new_transaction_by_type(:oracle)

        index = chain_size(summary_date)
        Logger.info("Oracle Scheduler: Scheduled during init - (index: #{index})")

        new_state_data =
          state_data
          |> Map.put(:summary_date, summary_date)
          |> Map.put(:indexes, %{summary_date => index})

        {:idle, new_state_data, {:next_event, :internal, :schedule}}

      _ ->
        Logger.info("Oracle Scheduler: waiting for Node Update Message")

        new_state_data =
          state_data
          |> Map.put(:indexes, %{})

        {:idle, new_state_data, []}
    end
  end

  def handle_event(
        :internal,
        :schedule,
        _state,
        data = %{polling_interval: polling_interval, indexes: indexes, summary_date: summary_date}
      ) do
    current_time = DateTime.utc_now() |> DateTime.truncate(:second)
    polling_date = next_date(polling_interval, current_time)

    polling_timer =
      case Map.get(data, :polling_timer) do
        nil ->
          schedule_new_polling(polling_date, current_time)

        timer ->
          Process.cancel_timer(timer)
          schedule_new_polling(polling_date, current_time)
      end

    index = Map.fetch!(indexes, summary_date)

    new_data =
      data
      |> Map.put(:polling_timer, polling_timer)
      |> Map.put(:polling_date, polling_date)
      |> Map.put(:next_address, Crypto.derive_oracle_address(summary_date, index + 1))

    {:next_state, :scheduled, new_data}
  end

  def handle_event(
        :internal,
        {:schedule_at, polling_date},
        :idle,
        data = %{summary_date: summary_date, indexes: indexes}
      ) do
    current_time = DateTime.utc_now() |> DateTime.truncate(:second)
    polling_timer = schedule_new_polling(polling_date, current_time)
    index = Map.fetch!(indexes, summary_date)

    new_data =
      data
      |> Map.put(:polling_timer, polling_timer)
      |> Map.put(:polling_date, polling_date)
      |> Map.put(:next_address, Crypto.derive_oracle_address(summary_date, index + 1))

    {:next_state, :scheduled, new_data}
  end

  def handle_event(:info, :node_up, :idle, state_data) do
    PubSub.unregister_to_node_up()
    {:idle, new_state_data, events} = start_scheduler(state_data)
    {:keep_state, new_state_data, events}
  end

  def handle_event(
        :info,
        {:new_transaction, address, :oracle, _timestamp},
        :triggered,
        data = %{summary_date: summary_date, indexes: indexes, next_address: next_address}
      )
      when address == next_address do
    PubSub.unregister_to_new_transaction_by_address(address)

    new_data =
      case Map.pop(data, :oracle_watcher) do
        {nil, data} ->
          data

        {pid, data} ->
          Process.exit(pid, :normal)
          data
      end

    new_data =
      case Map.get(indexes, summary_date) do
        nil ->
          new_data

        index ->
          # We increment the index since the tx is replicated
          Map.update!(new_data, :indexes, &Map.put(&1, summary_date, index + 1))
      end

    {:next_state, :confirmed, new_data, {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:new_transaction, address, :oracle, _timestamp},
        :scheduled,
        data = %{next_address: next_address, summary_date: summary_date, indexes: indexes}
      ) do
    Logger.debug(
      "Reschedule polling after reception of an oracle transaction in scheduled state instead of triggered state"
    )

    # We prevent non scheduled transactions to change
    new_data =
      if next_address == address do
        case Map.get(indexes, summary_date) do
          nil ->
            data

          index ->
            # We increment the index since the tx is replicated
            Map.update!(data, :indexes, &Map.put(&1, summary_date, index + 1))
        end
      else
        data
      end

    {:keep_state, new_data, {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        :poll,
        :scheduled,
        data = %{
          polling_date: polling_date,
          summary_date: summary_date
        }
      ) do
    if DateTime.diff(polling_date, summary_date, :second) == 0 do
      Archethic.OracleChain.update_summ_gen_addr()
      {:next_state, :triggered, data, {:next_event, :internal, :aggregate}}
    else
      {:next_state, :triggered, data, {:next_event, :internal, :fetch_data}}
    end
  end

  def handle_event(
        :internal,
        :fetch_data,
        :triggered,
        data = %{
          summary_date: summary_date,
          indexes: indexes
        }
      ) do
    Logger.debug("Oracle poll - state: #{inspect(data)}")

    index = Map.fetch!(indexes, summary_date)

    new_oracle_data = get_new_oracle_data(summary_date, index)

    authorized_nodes =
      summary_date
      |> P2P.authorized_nodes()
      |> Enum.filter(& &1.available?)

    storage_nodes =
      summary_date
      |> Crypto.derive_oracle_address(index + 1)
      |> Election.storage_nodes(authorized_nodes)

    tx = build_oracle_transaction(summary_date, index, new_oracle_data)

    with {:empty, false} <- {:empty, Enum.empty?(new_oracle_data)},
         {:trigger, true} <- {:trigger, trigger_node?(storage_nodes)},
         {:exists, false} <- {:exists, DB.transaction_exists?(tx.address)} do
      send_polling_transaction(tx)
      :keep_state_and_data
    else
      {:empty, true} ->
        Logger.debug("Oracle transaction skipped - no new data")
        {:keep_state_and_data, [{:next_event, :internal, :schedule}]}

      {:trigger, false} ->
        {:ok, pid} =
          DetectNodeResponsiveness.start_link(tx.address, fn count ->
            new_oracle_data = get_new_oracle_data(summary_date, index)
            new_data? = !Enum.empty?(new_oracle_data)

            if trigger_node?(storage_nodes, count) and new_data? do
              Logger.info("Oracle polling transaction ...attempt #{count}",
                transaction_address: Base.encode16(tx.address),
                transaction_type: :oracle
              )

              tx = build_oracle_transaction(summary_date, index, new_oracle_data)
              send_polling_transaction(tx)
            end
          end)

        Process.monitor(pid)
        {:keep_state, Map.put(data, :oracle_watcher, pid)}

      {:exists, true} ->
        Logger.warning("Transaction already exists - before sending",
          transaction_address: Base.encode16(tx.address),
          transaction_type: :oracle
        )

        {:keep_state_and_data, [{:next_event, :internal, :schedule}]}
    end
  end

  def handle_event(
        :internal,
        :aggregate,
        :triggered,
        data = %{summary_date: summary_date, summary_interval: summary_interval, indexes: indexes}
      )
      when is_map_key(indexes, summary_date) do
    Logger.debug("Oracle summary - state: #{inspect(data)}")

    index = Map.fetch!(indexes, summary_date)
    validation_nodes = get_validation_nodes(summary_date, index + 1)

    # Stop previous oracle retries when the summary is triggered
    case Map.get(data, :oracle_watcher) do
      nil ->
        :ignore

      pid ->
        Process.exit(pid, :normal)
    end

    tx_address =
      summary_date
      |> Crypto.derive_oracle_keypair(index + 1)
      |> elem(0)
      |> Crypto.derive_address()

    summary_watcher_pid =
      with {:trigger, true} <- {:trigger, trigger_node?(validation_nodes)},
           {:exists, false} <- {:exists, DB.transaction_exists?(tx_address)} do
        Logger.debug("Oracle transaction summary sending",
          transaction_address: Base.encode16(tx_address),
          transaction_type: :oracle_summary
        )

        send_summary_transaction(summary_date, index)
        nil
      else
        {:trigger, false} ->
          Logger.debug("Oracle summary skipped - not the trigger node",
            transaction_address: Base.encode16(tx_address),
            transaction_type: :oracle_summary
          )

          {:ok, pid} =
            DetectNodeResponsiveness.start_link(tx_address, fn count ->
              if trigger_node?(validation_nodes, count) do
                Logger.info("Oracle summary transaction ...attempt #{count}",
                  transaction_address: Base.encode16(tx_address),
                  transaction_type: :oracle_summary
                )

                send_summary_transaction(summary_date, index)
              end
            end)

          Process.monitor(pid)

          pid

        {:exists, true} ->
          Logger.warning("Oracle transaction already exists",
            transaction_address: Base.encode16(tx_address),
            transaction_type: :oracle_summary
          )

          nil
      end

    current_time = DateTime.utc_now() |> DateTime.truncate(:second)
    next_summary_date = next_date(summary_interval, current_time)
    Logger.info("Next Oracle Summary at #{DateTime.to_string(next_summary_date)}")

    new_data =
      data
      |> Map.put(:summary_date, next_summary_date)
      |> Map.put(:summary_watcher, summary_watcher_pid)
      |> Map.put(:next_address, Crypto.derive_oracle_address(next_summary_date, 1))
      |> Map.delete(:oracle_watcher)
      |> Map.update!(:indexes, fn indexes ->
        # Clean previous indexes
        indexes
        |> Map.keys()
        |> Enum.filter(&(DateTime.diff(&1, next_summary_date) < 0))
        |> Enum.reduce(indexes, &Map.delete(&2, &1))
      end)
      |> Map.update!(:indexes, fn indexes ->
        # Prevent overwrite, if the oracle transaction was faster than the summary processing
        if Map.has_key?(indexes, next_summary_date) do
          indexes
        else
          Map.put(indexes, next_summary_date, 0)
        end
      end)

    {:keep_state, new_data, {:next_event, :internal, :fetch_data}}
  end

  def handle_event(
        :internal,
        :aggregate,
        :triggered,
        data = %{summary_interval: summary_interval}
      ) do
    # Discard the oracle summary if there is not previous indexing

    current_time = DateTime.utc_now() |> DateTime.truncate(:second)
    next_summary_date = next_date(summary_interval, current_time)
    Logger.info("Next Oracle Summary at #{DateTime.to_string(next_summary_date)}")

    new_data =
      data
      |> Map.put(:summary_date, next_summary_date)
      |> Map.put(:indexes, %{next_summary_date => 0})
      |> Map.put(:polling_date, next_summary_date)
      |> Map.put(:next_address, Crypto.derive_oracle_address(next_summary_date, 1))

    {:keep_state, new_data, {:next_event, :internal, :fetch_data}}
  end

  def handle_event(
        :info,
        {:DOWN, _ref, :process, pid, {:shutdown, :hard_timeout}},
        :triggered,
        data = %{oracle_watcher: watcher_pid}
      )
      when pid == watcher_pid do
    {:keep_state, Map.delete(data, :oracle_watcher), {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:DOWN, _ref, :process, pid, _},
        :triggered,
        _data = %{oracle_watcher: watcher_pid}
      )
      when pid == watcher_pid do
    :keep_state_and_data
  end

  def handle_event(
        :info,
        {:DOWN, _ref, :process, pid, _},
        :triggered,
        _data = %{summary_watcher: watcher_pid}
      )
      when pid == watcher_pid do
    :keep_state_and_data
  end

  def handle_event(
        :info,
        {:DOWN, _ref, :process, pid, _},
        :scheduled,
        _data = %{oracle_watcher: watcher_pid}
      )
      when pid == watcher_pid do
    :keep_state_and_data
  end

  def handle_event(
        :info,
        {:DOWN, _ref, :process, pid, _},
        _state,
        data = %{summary_watcher: watcher_pid}
      )
      when pid == watcher_pid do
    {:keep_state, Map.delete(data, :summary_watcher)}
  end

  def handle_event(
        :info,
        {:DOWN, _ref, :process, _pid, _},
        _state,
        data
      ) do
    new_data =
      data
      |> Map.delete(:oracle_watcher)
      |> Map.delete(:summary_watcher)

    {:keep_state, new_data}
  end

  def handle_event(
        :info,
        {:node_update,
         %Node{authorized?: true, available?: true, first_public_key: first_public_key}},
        :idle,
        data = %{summary_interval: summary_interval, polling_interval: polling_interval}
      ) do
    if Crypto.first_node_public_key() == first_public_key do
      current_time = DateTime.utc_now() |> DateTime.truncate(:second)

      next_summary_date = next_date(summary_interval, current_time)
      index = chain_size(next_summary_date)

      other_authorized_nodes =
        P2P.authorized_and_available_nodes()
        |> Enum.reject(&(&1.first_public_key == first_public_key))

      Logger.info("Start the Oracle scheduler - (index: #{index})")
      PubSub.register_to_new_transaction_by_type(:oracle)

      case other_authorized_nodes do
        [] ->
          next_polling_date = next_date(polling_interval, current_time)

          new_data =
            data
            |> Map.put(:polling_date, next_polling_date)
            |> Map.put(:summary_date, next_summary_date)
            |> Map.put(:indexes, %{next_summary_date => index})

          {:keep_state, new_data, {:next_event, :internal, :schedule}}

        _ ->
          new_data =
            data
            |> Map.put(:polling_date, next_summary_date)
            |> Map.put(:summary_date, next_summary_date)
            |> Map.put(:indexes, %{next_summary_date => index})

          {:keep_state, new_data, {:next_event, :internal, {:schedule_at, next_summary_date}}}
      end
    else
      :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:node_update, %Node{authorized?: false, first_public_key: first_public_key}},
        _,
        data = %{polling_timer: polling_timer}
      ) do
    if first_public_key == Crypto.first_node_public_key() do
      PubSub.unregister_to_new_transaction_by_type(:oracle)
      Process.cancel_timer(polling_timer)

      new_data =
        data
        |> Map.delete(:polling_timer)

      {:next_state, :idle, new_data}
    else
      :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:node_update,
         %Node{authorized?: true, available?: false, first_public_key: first_public_key}},
        _state,
        data = %{polling_timer: polling_timer}
      ) do
    if first_public_key == Crypto.first_node_public_key() do
      PubSub.unregister_to_new_transaction_by_type(:oracle)
      Process.cancel_timer(polling_timer)

      new_data =
        data
        |> Map.delete(:polling_timer)

      {:next_state, :idle, new_data}
    else
      :keep_state_and_data
    end
  end

  def handle_event(:info, {:node_update, _}, _state, _data),
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

  def handle_event(_event_type, _event, :idle, _data), do: :keep_state_and_data

  defp schedule_new_polling(next_polling_date, current_time = %DateTime{}) do
    Logger.info("Next oracle polling at #{DateTime.to_string(next_polling_date)}")

    Process.send_after(
      self(),
      :poll,
      DateTime.diff(next_polling_date, current_time, :millisecond)
    )
  end

  defp trigger_node?(validation_nodes, count \\ 0) do
    %Node{first_public_key: initiator_key} =
      validation_nodes
      |> Enum.at(count)

    initiator_key == Crypto.first_node_public_key()
  end

  defp send_polling_transaction(tx) do
    Task.start(fn -> Archethic.send_new_transaction(tx) end)

    Logger.debug("New data pushed to the oracle",
      transaction_address: Base.encode16(tx.address),
      transaction_type: :oracle
    )
  end

  defp build_oracle_transaction(summary_date, index, oracle_data) do
    {prev_pub, prev_pv} = Crypto.derive_oracle_keypair(summary_date, index)

    {next_pub, _} = Crypto.derive_oracle_keypair(summary_date, index + 1)

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
  end

  defp send_summary_transaction(summary_date, index) do
    oracle_chain =
      summary_date
      |> Crypto.derive_oracle_address(index)
      |> get_chain()

    {prev_pub, prev_pv} = Crypto.derive_oracle_keypair(summary_date, index)
    {next_pub, _} = Crypto.derive_oracle_keypair(summary_date, index + 1)

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

    if DB.transaction_exists?(tx.address) do
      Logger.debug(
        "Transaction Already Exists:oracle summary transaction - aggregation: #{inspect(aggregated_content)}",
        transaction_address: Base.encode16(tx.address),
        transaction_type: :oracle_summary
      )
    else
      Logger.debug(
        "Sending oracle summary transaction - aggregation: #{inspect(aggregated_content)}",
        transaction_address: Base.encode16(tx.address),
        transaction_type: :oracle_summary
      )

      Task.start(fn -> Archethic.send_new_transaction(tx) end)
    end
  end

  defp get_chain(address, opts \\ [], acc \\ []) do
    case TransactionChain.get(address, [data: [:content], validation_stamp: [:timestamp]], opts) do
      {transactions, false, _paging_state} ->
        acc ++ transactions

      {transactions, true, paging_state} ->
        get_chain(address, [paging_state: paging_state], acc ++ transactions)
    end
  end

  defp chain_size(summary_date = %DateTime{}) do
    oracle_genesis_address = Crypto.derive_oracle_address(summary_date, 0)
    {last_address, _} = TransactionChain.get_last_address(oracle_genesis_address)
    TransactionChain.size(last_address)
  end

  defp get_oracle_data(address) do
    case TransactionChain.get_transaction(address, data: [:content]) do
      {:ok, %Transaction{data: %TransactionData{content: previous_content}}} ->
        Jason.decode!(previous_content)

      _ ->
        %{}
    end
  end

  defp next_date(interval, from_date = %DateTime{}) do
    cron_expression = CronParser.parse!(interval, true)
    naive_from_date = from_date |> DateTime.truncate(:second) |> DateTime.to_naive()

    if Crontab.DateChecker.matches_date?(cron_expression, naive_from_date) do
      cron_expression
      |> CronScheduler.get_next_run_dates(naive_from_date)
      |> Enum.at(1)
      |> DateTime.from_naive!("Etc/UTC")
    else
      cron_expression
      |> CronScheduler.get_next_run_date!(naive_from_date)
      |> DateTime.from_naive!("Etc/UTC")
    end
  end

  defp get_validation_nodes(summary_date, index) do
    authorized_nodes =
      Enum.filter(
        P2P.list_nodes(),
        &(&1.authorized? && DateTime.diff(&1.authorization_date, summary_date) <= 0 &&
            &1.available?)
      )

    summary_date
    |> Crypto.derive_oracle_address(index)
    |> Election.storage_nodes(authorized_nodes)
  end

  defp get_new_oracle_data(summary_date, index) do
    summary_date
    |> Crypto.derive_oracle_address(index)
    |> get_oracle_data()
    |> Services.fetch_new_data()
  end
end
