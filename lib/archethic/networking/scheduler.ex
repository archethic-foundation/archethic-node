defmodule Archethic.Networking.Scheduler do
  @moduledoc false

  use GenServer
  @vsn 1

  alias Archethic.Crypto

  alias Archethic.Networking.IPLookup
  alias Archethic.Networking.PortForwarding

  alias Archethic.P2P
  alias Archethic.P2P.GeoPatch
  alias Archethic.P2P.Listener, as: P2PListener
  alias Archethic.P2P.Node
  alias Archethic.P2P.NodeConfig

  alias Archethic.PubSub

  alias Archethic.Replication

  alias Archethic.SelfRepair.NetworkChain

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Utils

  alias ArchethicWeb.Endpoint, as: WebEndpoint

  require Logger

  @geopatch_update_time Application.compile_env!(:archethic, :geopatch_update_time)

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg)
  end

  def init(arg) do
    interval = Keyword.fetch!(arg, :interval)

    if Archethic.up?() do
      timer = schedule_update(interval)
      {:ok, %{timer: timer, interval: interval}}
    else
      # node still bootstrapping , wait for it to finish Bootstrap
      Logger.info(" Networking Scheduler: Waiting for Node to complete Bootstrap. ")

      PubSub.register_to_node_status()

      {:ok, %{interval: interval}}
    end
  end

  def handle_info(:node_up, state = %{interval: interval}) do
    Logger.info("Networking Scheduler: Starting...")

    new_state =
      state
      |> Map.put(:timer, schedule_update(interval))

    {:noreply, new_state, :hibernate}
  end

  def handle_info(:node_down, %{interval: interval, timer: timer}) do
    Logger.info("Networking Scheduler: Stopping...")
    Process.cancel_timer(timer)
    {:noreply, %{interval: interval}, :hibernate}
  end

  def handle_info(:node_down, %{interval: interval}) do
    Logger.info("Networking Scheduler: Stopping...")
    {:noreply, %{interval: interval}, :hibernate}
  end

  def handle_info(:update, state = %{interval: interval}) do
    timer =
      case Map.get(state, :timer) do
        nil ->
          schedule_update(interval)

        old_timer ->
          Process.cancel_timer(old_timer)
          schedule_update(interval)
      end

    Task.Supervisor.start_child(Archethic.task_supervisors(), fn -> do_update() end)

    {:noreply, Map.put(state, :timer, timer)}
  end

  defp schedule_update(interval) do
    Process.send_after(self(), :update, Utils.time_offset(interval))
  end

  defp do_update do
    Logger.info("Start networking update")

    node =
      %Node{ip: prev_ip, last_address: last_address, origin_public_key: origin_public_key} =
      P2P.get_node_info()

    with {:ok, p2p_port, web_port} <- open_ports(),
         {:ok, ip} <- IPLookup.get_node_ip(),
         true <- prev_ip != ip,
         {:ok, %Transaction{data: %TransactionData{code: code}}} <-
           TransactionChain.get_transaction(last_address, data: [:code]) do
      node_config = %NodeConfig{
        NodeConfig.from_node(node)
        | origin_certificate: Crypto.get_key_certificate(origin_public_key),
          geo_patch: GeoPatch.from_ip(ip),
          geo_patch_update: DateTime.add(DateTime.utc_now(), @geopatch_update_time, :millisecond),
          port: p2p_port,
          http_port: web_port
      }

      tx =
        Transaction.new(:node, %TransactionData{
          code: code,
          content: Node.encode_transaction_content(node_config)
        })

      Archethic.send_new_transaction(tx, forward?: true)
      handle_new_ip(tx)
    else
      :error -> Logger.warning("Cannot open port")
      false -> Logger.debug("Skip node update: Same IP - no need to send a new node transaction")
      {:error, _} -> Logger.warning("Cannot fetch IP")
    end
  end

  defp open_ports do
    p2p_port = Application.get_env(:archethic, P2PListener) |> Keyword.fetch!(:port)
    web_port = Application.get_env(:archethic, WebEndpoint) |> get_in([:http, :port])

    with {:ok, p2p_port} <- PortForwarding.try_open_port(p2p_port, false),
         {:ok, web_port} <- PortForwarding.try_open_port(web_port, false) do
      {:ok, p2p_port, web_port}
    end
  end

  defp handle_new_ip(%Transaction{address: tx_address, data: transaction_data}) do
    nodes =
      P2P.authorized_and_available_nodes()
      |> Enum.filter(&P2P.node_connected?/1)
      |> P2P.sort_by_nearest_nodes()

    case Utils.await_confirmation(tx_address, nodes) do
      {:ok, validated_transaction = %Transaction{address: ^tx_address, data: ^transaction_data}} ->
        genesis_address = Crypto.first_node_public_key() |> Crypto.derive_address()

        Replication.sync_transaction_chain(validated_transaction, genesis_address)

      {:ok, _} ->
        Logger.warning("Network Scheduler received a non corresponding node transaction")

      {:error, :network_issue} ->
        Logger.warning("Network Scheduler did not received confirmation for new node tx")
    end

    NetworkChain.asynchronous_resync_many([:node, :oracle, :node_shared_secrets, :origin])
  end
end
