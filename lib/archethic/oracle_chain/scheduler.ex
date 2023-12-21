defmodule Archethic.OracleChain.Scheduler do
  @moduledoc """
  Manage the scheduling of the oracle transactions
  """
  alias Archethic
  alias Archethic.{Crypto, Election, P2P, P2P.Node, PubSub, Utils}
  alias Archethic.{OracleChain, TransactionChain, Utils.DetectNodeResponsiveness}
  alias OracleChain.{Services, Summary}
  alias TransactionChain.{Transaction, TransactionData}

  use GenStateMachine, callback_mode: [:handle_event_function]
  @vsn Mix.Project.config()[:version]

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
    # Set trap_exit globally for the process
    Process.flag(:trap_exit, true)

    state_data =
      %{}
      |> Map.put(:polling_interval, polling_interval)
      |> Map.put(:summary_interval, summary_interval)

    if Archethic.up?() do
      # when node is already bootstrapped, - handles scheduler crash
      {state, new_state_data, events} = start_scheduler(state_data)
      {:ok, state, new_state_data, events}
    else
      # node still bootstrapping , wait for it to finish Bootstrap
      Logger.info(" Oracle Scheduler: Waiting for Node to complete Bootstrap. ")

      PubSub.register_to_node_status()

      {:ok, :idle, state_data}
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
          Map.get(state_data, :summary_interval) |> Utils.next_date(DateTime.utc_now())

        PubSub.register_to_new_transaction_by_type(:oracle)
        PubSub.register_to_new_transaction_by_type(:oracle_summary)

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
    polling_date = Utils.next_date(polling_interval, DateTime.utc_now())

    polling_timer =
      case Map.get(data, :polling_timer) do
        nil ->
          schedule_new_polling(polling_date)

        timer ->
          Process.cancel_timer(timer)
          schedule_new_polling(polling_date)
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
    polling_timer = schedule_new_polling(polling_date)
    index = Map.fetch!(indexes, summary_date)

    new_data =
      data
      |> Map.put(:polling_timer, polling_timer)
      |> Map.put(:polling_date, polling_date)
      |> Map.put(:next_address, Crypto.derive_oracle_address(summary_date, index + 1))

    {:next_state, :scheduled, new_data}
  end

  def handle_event(:info, :node_up, _, state_data) do
    {:idle, new_state_data, events} = start_scheduler(state_data)
    {:keep_state, new_state_data, events}
  end

  def handle_event(:info, :node_down, _, %{
        polling_interval: polling_interval,
        summary_interval: summary_interval,
        polling_timer: polling_timer
      }) do
    Process.cancel_timer(polling_timer)

    {:next_state, :idle,
     %{
       polling_interval: polling_interval,
       summary_interval: summary_interval
     }}
  end

  def handle_event(:info, :node_down, _, %{
        polling_interval: polling_interval,
        summary_interval: summary_interval
      }) do
    {:next_state, :idle,
     %{
       polling_interval: polling_interval,
       summary_interval: summary_interval
     }}
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
      case Map.pop(data, :watcher) do
        {nil, data} ->
          data

        {pid, data} ->
          Process.exit(pid, :kill)
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

  def handle_event(:info, {:new_transaction, _, :oracle_summary, _timestamp}, :triggered, data) do
    new_data =
      case Map.pop(data, :watcher) do
        {nil, data} ->
          data

        {pid, data} ->
          Process.exit(pid, :kill)
          data
      end

    new_data = update_summary_date(new_data)
    {:keep_state, new_data, {:next_event, :internal, :fetch_data}}
  end

  def handle_event(
        :info,
        {:new_transaction, _address, :oracle_summary, _timestamp},
        :scheduled,
        data
      ) do
    Logger.debug(
      "Reschedule polling after reception of an oracle summary transaction in scheduled state instead of triggered state"
    )

    case Map.get(data, :polling_timer) do
      nil ->
        :skip

      timer ->
        Process.cancel_timer(timer)
    end

    new_data = update_summary_date(data)
    {:next_state, :triggered, new_data, {:next_event, :internal, :fetch_data}}
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
    Logger.debug("Oracle polling in process")

    if DateTime.diff(polling_date, summary_date, :second) >= 0 do
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

    authorized_nodes = P2P.authorized_and_available_nodes()

    storage_nodes =
      summary_date
      |> Crypto.derive_oracle_address(index + 1)
      |> Election.storage_nodes(authorized_nodes)

    tx = build_oracle_transaction(summary_date, index, new_oracle_data)

    with {:empty, false} <- {:empty, Enum.empty?(new_oracle_data)},
         {:exists, false} <- {:exists, TransactionChain.transaction_exists?(tx.address)},
         {:trigger, true} <- {:trigger, trigger_node?(storage_nodes)} do
      send_polling_transaction(tx)
      :keep_state_and_data
    else
      {:empty, true} ->
        Logger.debug("Oracle transaction skipped - no new data")
        {:keep_state_and_data, [{:next_event, :internal, :schedule}]}

      {:trigger, false} ->
        {:ok, pid} =
          DetectNodeResponsiveness.start_link(tx.address, length(storage_nodes), fn count ->
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

        {:keep_state, Map.put(data, :watcher, pid)}

      {:exists, true} ->
        Logger.warning("Transaction already exists - before sending",
          transaction_address: Base.encode16(tx.address),
          transaction_type: :oracle
        )

        # Advance in the index as the transaction already exists (hence the previous index was out of date)
        new_indexes = Map.update!(indexes, summary_date, &(&1 + 1))
        {:keep_state, Map.put(data, :indexes, new_indexes), [{:next_event, :internal, :schedule}]}
    end
  end

  def handle_event(
        :internal,
        :aggregate,
        :triggered,
        data = %{summary_date: summary_date, indexes: indexes}
      )
      when is_map_key(indexes, summary_date) do
    Logger.debug("Oracle summary - state: #{inspect(data)}")

    index = Map.fetch!(indexes, summary_date)

    tx_address = summary_date |> Crypto.derive_oracle_address(index + 1)

    authorized_nodes = P2P.authorized_and_available_nodes()
    storage_nodes = tx_address |> Election.storage_nodes(authorized_nodes)

    watcher_pid =
      with {:exists, false} <- {:exists, TransactionChain.transaction_exists?(tx_address)},
           {:trigger, true} <- {:trigger, trigger_node?(storage_nodes)} do
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
            DetectNodeResponsiveness.start_link(tx_address, length(storage_nodes), fn count ->
              if trigger_node?(storage_nodes, count) do
                Logger.info("Oracle summary transaction ...attempt #{count}",
                  transaction_address: Base.encode16(tx_address),
                  transaction_type: :oracle_summary
                )

                send_summary_transaction(summary_date, index)
              end
            end)

          pid

        {:exists, true} ->
          Logger.warning("Oracle transaction already exists",
            transaction_address: Base.encode16(tx_address),
            transaction_type: :oracle_summary
          )

          nil
      end

    {:keep_state, Map.put(data, :watcher, watcher_pid)}
  end

  def handle_event(
        :internal,
        :aggregate,
        :triggered,
        data = %{summary_interval: summary_interval}
      ) do
    # Discard the oracle summary if there is not previous indexing
    next_summary_date = Utils.next_date(summary_interval, DateTime.utc_now())
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
        {:EXIT, pid, {:shutdown, :hard_timeout}},
        :triggered,
        data = %{watcher: watcher_pid}
      )
      when pid == watcher_pid do
    {:keep_state, Map.delete(data, :watcher), {:next_event, :internal, :schedule}}
  end

  def handle_event(
        :info,
        {:EXIT, pid, _},
        _state,
        data = %{watcher: watcher_pid}
      )
      when watcher_pid == pid do
    {:keep_state, Map.delete(data, :watcher)}
  end

  def handle_event(
        :info,
        {:EXIT, _pid, _},
        _state,
        _data
      ) do
    :keep_state_and_data
  end

  def handle_event(
        :info,
        {:node_update,
         %Node{authorized?: true, available?: true, first_public_key: first_public_key}},
        :idle,
        data = %{summary_interval: summary_interval, polling_interval: polling_interval}
      ) do
    if Crypto.first_node_public_key() == first_public_key do
      next_summary_date = Utils.next_date(summary_interval, DateTime.utc_now())
      index = chain_size(next_summary_date)

      other_authorized_nodes =
        P2P.authorized_and_available_nodes()
        |> Enum.reject(&(&1.first_public_key == first_public_key))

      Logger.info("Start the Oracle scheduler - (index: #{index})")
      PubSub.register_to_new_transaction_by_type(:oracle)
      PubSub.register_to_new_transaction_by_type(:oracle_summary)

      case other_authorized_nodes do
        [] ->
          next_polling_date = Utils.next_date(polling_interval, DateTime.utc_now())

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
      PubSub.unregister_to_new_transaction_by_type(:oracle_summary)
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

  defp update_summary_date(data = %{summary_interval: summary_interval}) do
    OracleChain.update_summ_gen_addr()

    next_summary_date = Utils.next_date(summary_interval, DateTime.utc_now())
    Logger.info("Next Oracle Summary at #{DateTime.to_string(next_summary_date)}")

    data
    |> Map.put(:summary_date, next_summary_date)
    |> Map.put(:next_address, Crypto.derive_oracle_address(next_summary_date, 1))
    |> Map.delete(:watcher)
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
  end

  defp schedule_new_polling(next_polling_date) do
    Logger.info("Next oracle polling at #{DateTime.to_string(next_polling_date)}")

    Process.send_after(
      self(),
      :poll,
      DateTime.diff(next_polling_date, DateTime.utc_now(), :millisecond)
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
      |> TransactionChain.get(data: [:content], validation_stamp: [:timestamp])
      |> Enum.to_list()

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

    if TransactionChain.transaction_exists?(tx.address) do
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

  defp chain_size(summary_date = %DateTime{}) do
    Crypto.derive_oracle_address(summary_date, 0)
    |> TransactionChain.get_size()
  end

  defp get_oracle_data(address) do
    case TransactionChain.get_transaction(address, data: [:content]) do
      {:ok, %Transaction{data: %TransactionData{content: previous_content}}} ->
        Jason.decode!(previous_content)

      _ ->
        %{}
    end
  end

  defp get_new_oracle_data(summary_date, index) do
    summary_date
    |> Crypto.derive_oracle_address(index)
    |> get_oracle_data()
    |> Services.fetch_new_data()
  end

  def code_change(_old_vsn, state, data, _extra), do: {:ok, state, data}
end
