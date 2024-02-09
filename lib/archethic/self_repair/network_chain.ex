defmodule Archethic.SelfRepair.NetworkChain do
  @moduledoc """
  Synchronization of one or multiple network chains.
  """
  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.OracleChain

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair

  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.Utils

  @type type() :: :origin | :oracle | :node | :node_shared_secrets

  @doc """
  Synchronize the network chain of given type.
  It runs in a separate process. At most once is running concurrently.
  """
  @spec asynchronous_resync(type()) :: :ok
  def asynchronous_resync(network_chain_type) do
    Utils.run_exclusive(network_chain_type, &synchronous_resync/1)
  end

  @doc """
  Synchronize the network chains of given types.
  Every sync is done in its own process, at most once sync per type is running concurrently.
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

    case P2P.fetch_nodes_list(false, P2P.authorized_and_available_nodes()) do
      {:ok, nodes} ->
        nodes_to_resync = Enum.filter(nodes, &node_require_resync?/1)

        # Load the latest node transactions
        Task.Supervisor.async_stream_nolink(
          Archethic.TaskSupervisor,
          nodes_to_resync,
          fn %Node{first_public_key: first_public_key, last_address: last_address} ->
            genesis_address = Crypto.derive_address(first_public_key)
            SelfRepair.replicate_transaction(last_address, genesis_address)
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

    genesis_address = get_genesis_address(type)

    case verify_synchronization(type) do
      {:error, addresses} when is_list(addresses) ->
        Task.Supervisor.async_stream_nolink(
          Archethic.TaskSupervisor,
          addresses,
          &SelfRepair.replicate_transaction(&1, genesis_address),
          ordered: false,
          on_timeout: :kill_task
        )
        |> Stream.run()

      _ ->
        :ok
    end
  end

  @doc """
  Verify if the last stored transaction is the last one on the network
  """
  @spec verify_synchronization(atom()) :: :ok | :error | {:error, list(Crypto.prepended_hash())}
  def verify_synchronization(:origin) do
    genesis_addresses = SharedSecrets.genesis_address(:origin)

    last_addresses =
      Task.Supervisor.async_stream(TaskSupervisor, genesis_addresses, fn genesis ->
        validate_last_address(genesis)
      end)
      |> Stream.filter(&match?({:ok, {:error, _}}, &1))
      |> Enum.flat_map(fn {_, {_, last_address}} -> last_address end)

    if Enum.empty?(last_addresses) do
      :ok
    else
      {:error, last_addresses}
    end
  end

  def verify_synchronization(:node_shared_secrets) do
    genesis_address = SharedSecrets.genesis_address(:node_shared_secrets)
    last_schedule_date = SharedSecrets.get_last_scheduling_date(DateTime.utc_now())
    do_verify_synchronization(genesis_address, last_schedule_date)
  end

  def verify_synchronization(:oracle) do
    genesis_address = OracleChain.genesis_address()
    last_schedule_date = OracleChain.get_last_scheduling_date(DateTime.utc_now())
    do_verify_synchronization(genesis_address, last_schedule_date)
  end

  defp get_genesis_address(:oracle), do: OracleChain.genesis_address()

  defp get_genesis_address(type) when type in [:origin, :node_shared_secrets],
    do: SharedSecrets.genesis_address(type)

  defp do_verify_synchronization(nil, _), do: :ok

  defp do_verify_synchronization(genesis_address, last_schedule_date) do
    if valid_schedule?(genesis_address, last_schedule_date) do
      :ok
    else
      validate_last_address(genesis_address)
    end
  end

  defp valid_schedule?(genesis_address, last_schedule_date) do
    last_transaction =
      TransactionChain.get_last_transaction(genesis_address, validation_stamp: [:timestamp])

    case last_transaction do
      {:ok, %Transaction{validation_stamp: %ValidationStamp{timestamp: validation_timestamp}}} ->
        DateTime.compare(validation_timestamp, last_schedule_date) != :lt

      _ ->
        false
    end
  end

  defp validate_last_address(genesis_address) do
    nodes = Election.chain_storage_nodes(genesis_address, P2P.authorized_and_available_nodes())

    {_, local_last_address_timestamp} = TransactionChain.get_last_address(genesis_address)

    case TransactionChain.fetch_last_address(genesis_address, nodes,
           consistency_level: 8,
           acceptance_resolver: &(&1.timestamp > local_last_address_timestamp)
         ) do
      {:ok, remote_last_address} ->
        {:error, [remote_last_address]}

      {:error, :acceptance_failed} ->
        :ok

      {:error, :network_issue} ->
        :error
    end
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
