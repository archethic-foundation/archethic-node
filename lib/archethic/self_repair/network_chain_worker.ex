defmodule Archethic.SelfRepair.NetworkChainWorker do
  @moduledoc false
  use GenStateMachine, callback_mode: [:handle_event_function]

  alias Archethic.OracleChain
  alias Archethic.P2P
  alias Archethic.Reward
  alias Archethic.SelfRepair
  alias Archethic.SharedSecrets
  alias Archethic.TransactionChain

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
  Resync a network chain. Asynchronous by default.
  """
  @spec resync(type(), boolean()) :: :ok
  def resync(type, async) do
    if async do
      GenStateMachine.cast(via_tuple(type), :resync)
    else
      resync_network_chain(type)
    end
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
    task = Task.async(fn -> resync_network_chain(type) end)
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

  defp resync_network_chain(:node) do
    # Refresh the local P2P view (load the nodes in memory)
    Archethic.Bootstrap.Sync.load_node_list()

    # Load the latest node transactions
    Task.Supervisor.async_stream_nolink(
      Archethic.TaskSupervisor,
      P2P.authorized_and_available_nodes(),
      &resync_chain_if_needed(&1.last_address, &1.last_address),
      ordered: false,
      on_timeout: :kill_task,
      timeout: 5000
    )
    |> Stream.run()
  end

  defp resync_network_chain(type) do
    addresses =
      case type do
        :node_shared_secrets ->
          [SharedSecrets.genesis_address(:node_shared_secrets)]

        :oracle ->
          [OracleChain.get_current_genesis_address()]

        :reward ->
          [Reward.genesis_address()]

        :origin ->
          SharedSecrets.genesis_address(:origin)
      end

    Task.Supervisor.async_stream_nolink(
      Archethic.TaskSupervisor,
      addresses,
      fn genesis_address ->
        {local_last_address, _} = TransactionChain.get_last_address(genesis_address)
        resync_chain_if_needed(genesis_address, local_last_address)
      end,
      ordered: false,
      on_timeout: :kill_task,
      timeout: 5000
    )
    |> Stream.run()
  end

  defp resync_chain_if_needed(genesis_address, local_last_address) do
    with {:ok, remote_last_addr} <- TransactionChain.resolve_last_address(genesis_address),
         false <- remote_last_addr == local_last_address do
      SelfRepair.resync(genesis_address, remote_last_addr)
    end
  end
end
