defmodule Archethic.SelfRepair.NetworkChain do
  @moduledoc """
  Synchronization of one or multiple network chains.
  Asynchronous functions use a worker to avoid concurrent runs.
  """
  alias Archethic.OracleChain
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.Reward
  alias Archethic.SelfRepair
  alias Archethic.SharedSecrets
  alias Archethic.TransactionChain
  alias Archethic.Utils.DistinctEffectWorker

  @type type() :: :origin | :reward | :oracle | :node | :node_shared_secrets

  @doc """
  Synchronize the network chain of given type.
  It runs in a worker. Skips if worker is already running.
  """

  @spec asynchronous_resync(type()) :: :ok
  def asynchronous_resync(network_chain_type) do
    DistinctEffectWorker.run(network_chain_type, &synchronous_resync/1)
  end

  @doc """
  Synchronize the network chains of given types.
  Every sync is done in its own worker, skip those already running.
  """
  @spec asynchronous_resync_many(list(type())) :: :ok
  def asynchronous_resync_many(network_chain_types) do
    Enum.each(
      network_chain_types,
      &asynchronous_resync(&1)
    )
  end

  @doc """
  Synchronize the network chain of given type.
  Blocks the caller.
  """
  @spec synchronous_resync(type()) :: :ok | {:error, :network_issue}
  def synchronous_resync(:node) do
    :telemetry.execute([:archethic, :self_repair, :resync], %{count: 1}, %{network_chain: :node})

    case P2P.fetch_nodes_list() do
      {:ok, nodes} ->
        nodes_to_resync = Enum.filter(nodes, &node_require_resync?/1)

        # Load the latest node transactions
        Task.Supervisor.async_stream_nolink(
          Archethic.TaskSupervisor,
          nodes_to_resync,
          fn %Node{last_address: last_address} ->
            SelfRepair.replicate_transaction(last_address)
          end,
          ordered: false,
          on_timeout: :kill_task,
          timeout: 5000
        )
        |> Stream.run()

      {:error, :network_issue} ->
        {:error, :network_issue}
    end
  end

  def synchronous_resync(type) do
    :telemetry.execute([:archethic, :self_repair, :resync], %{count: 1}, %{network_chain: type})

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
        with {local_last_address, _} <- TransactionChain.get_last_address(genesis_address),
             {:ok, remote_last_address} <- TransactionChain.resolve_last_address(genesis_address),
             false <- remote_last_address == local_last_address do
          SelfRepair.replicate_transaction(remote_last_address)
        end
      end,
      ordered: false,
      on_timeout: :kill_task,
      timeout: 5000
    )
    |> Stream.run()
  end

  @doc """
  Synchronize multiple network chains
  They all run in parallel but we block caller until they are all done.
  """
  @spec synchronous_resync_many(list(type())) :: :ok
  def synchronous_resync_many(network_chain_types) do
    Task.Supervisor.async_stream_nolink(
      Archethic.TaskSupervisor,
      network_chain_types,
      &synchronous_resync(&1),
      ordered: false,
      on_timeout: :kill_task,
      timeout: 5_000
    )
    |> Stream.run()
  end

  defp node_require_resync?(remote_node) do
    case P2P.get_node_info(remote_node.first_public_key) do
      {:ok, local_node} ->
        local_node.last_public_key != remote_node.last_public_key

      {:error, _} ->
        true
    end
  end
end
