defmodule Archethic.SelfRepair.NetworkChainWorker do
  @moduledoc false
  use GenStateMachine, callback_mode: [:handle_event_function]

  alias Archethic.SelfRepair.NetworkChain

  require Logger

  @type type() :: :origin | :reward | :oracle | :node | :node_shared_secrets

  # ------------------------------------------------------
  #               _
  #    __ _ _ __ (_)
  #   / _` | '_ \| |
  #  | (_| | |_) | |
  #   \__,_| .__/|_|
  #        |_|
  # ------------------------------------------------------
  @spec start_link(type()) :: {:ok, pid()} | {:error, {:already_started, pid()}}
  def start_link(type) do
    GenStateMachine.start_link(__MODULE__, type, name: via_tuple(type))
  end

  @doc """
  Asynchronously synchronize a network chain.
  Concurrent runs use the same worker.
  """
  @spec resync(type()) :: :ok
  def resync(type) do
    GenStateMachine.cast(via_tuple(type), :resync)
  end

  # ------------------------------------------------------
  #            _ _ _                _
  #   ___ __ _| | | |__   __ _  ___| | _____
  #  / __/ _` | | | '_ \ / _` |/ __| |/ / __|
  # | (_| (_| | | | |_) | (_| | (__|   <\__ \
  #  \___\__,_|_|_|_.__/ \__,_|\___|_|\_|___/
  #
  # ------------------------------------------------------

  def init(type) do
    {:ok, :idle, %{type: type}}
  end

  # ------------------------------------------------------
  def handle_event(:cast, :resync, :idle, data = %{type: type}) do
    task = Task.async(fn -> NetworkChain.synchronous_resync(type) end)
    new_data = Map.put(data, :task, task)

    Logger.info("SelfRepair: network chain #{type} synchronization started")

    {:next_state, :running, new_data}
  end

  def handle_event(:cast, :resync, :running, _data) do
    :keep_state_and_data
  end

  # ------------------------------------------------------
  def handle_event(:info, {ref, _result}, :running, %{task: %Task{ref: ref}}) do
    # we don't care about the result, we'll only deal with the DOWN
    :keep_state_and_data
  end

  def handle_event(
        :info,
        {:DOWN, _ref, :process, _pid, reason},
        :running,
        data = %{type: type}
      ) do
    case reason do
      :normal ->
        Logger.info("SelfRepair: network chain #{type} synchronization success")

      _ ->
        Logger.info("SelfRepair: network chain #{type} synchronization failure: #{reason}")
    end

    new_data = Map.put(data, :task, nil)
    {:next_state, :idle, new_data}
  end

  # ------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  #
  # ------------------------------------------------------
  defp via_tuple(type) do
    {:via, Registry, {Archethic.SelfRepair.WorkerRegistry, type}}
  end
end
