defmodule Archethic.SelfRepair.NetworkChain do
  @moduledoc """
  Synchronization of one or multiple network chains.
  Asynchronous functions use a NetworkChainWorker to avoid concurrent runs.
  """
  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.Reward
  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.NetworkChainWorker
  alias Archethic.SharedSecrets
  alias Archethic.TransactionChain

  @doc """
  Synchronize the network chain of given type.
  It runs in a worker. Skips if worker is already running.
  """
  @spec asynchronous_resync(NetworkChainWorker.type()) :: :ok
  def asynchronous_resync(network_chain_type) do
    NetworkChainWorker.resync(network_chain_type)
  end

  @doc """
  Synchronize the network chains of given types.
  Every sync is done in its own worker, skip those already running.
  """
  @spec asynchronous_resync_many(list(NetworkChainWorker.type())) :: :ok
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
  @spec synchronous_resync(NetworkChainWorker.type()) :: :ok | {:error, :network_issue}
  def synchronous_resync(:node) do
    :telemetry.execute([:archethic, :self_repair, :resync], %{count: 1}, %{network_chain: :node})

    case P2P.fetch_nodes_list() do
      {:ok, nodes} ->
        nodes_to_resync = Enum.filter(nodes, &node_require_resync?/1)

        # Load the latest node transactions
        Task.Supervisor.async_stream_nolink(
          Archethic.TaskSupervisor,
          nodes_to_resync,
          fn %Node{first_public_key: first_public_key, last_address: last_address} ->
            SelfRepair.resync(
              Crypto.derive_address(first_public_key),
              last_address
            )
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
        with false <- SelfRepair.repair_in_progress?(genesis_address),
             {local_last_address, _} <- TransactionChain.get_last_address(genesis_address),
             {:ok, remote_last_address} <- TransactionChain.resolve_last_address(genesis_address),
             false <- remote_last_address == local_last_address do
          SelfRepair.resync(genesis_address, remote_last_address)
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
  @spec synchronous_resync_many(list(NetworkChainWorker.type())) :: :ok
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
