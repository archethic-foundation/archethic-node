defmodule Archethic.Networking.Scheduler do
  @moduledoc false

  use GenServer
  @vsn Mix.Project.config()[:version]

  alias Archethic.{Crypto, P2P, P2P.Node, Networking, TaskSupervisor, Utils, PubSub}
  alias Archethic.{SelfRepair, TransactionChain}

  alias Networking.{IPLookup, PortForwarding}
  alias TransactionChain.{Transaction, TransactionData}

  alias P2P.Listener, as: P2PListener
  alias ArchethicWeb.Endpoint, as: WebEndpoint

  require Logger

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

    Task.Supervisor.start_child(TaskSupervisor, fn -> do_update() end)

    {:noreply, Map.put(state, :timer, timer)}
  end

  defp schedule_update(interval) do
    Process.send_after(self(), :update, Utils.time_offset(interval) * 1000)
  end

  defp do_update do
    Logger.info("Start networking update")

    with {:ok, p2p_port, web_port} <- open_ports(),
         {:ok, ip} <- IPLookup.get_node_ip(),
         {:ok, %Node{ip: prev_ip, reward_address: reward_address, transport: transport}}
         when prev_ip != ip <- P2P.get_node_info(Crypto.first_node_public_key()),
         genesis_address <- Crypto.first_node_public_key() |> Crypto.derive_address(),
         {:ok, %Transaction{data: %TransactionData{code: code}}} <-
           TransactionChain.get_last_transaction(genesis_address, data: [:code]) do
      origin_public_key = Crypto.origin_node_public_key()
      key_certificate = Crypto.get_key_certificate(origin_public_key)

      tx =
        Transaction.new(:node, %TransactionData{
          code: code,
          content:
            Node.encode_transaction_content(
              ip,
              p2p_port,
              web_port,
              transport,
              reward_address,
              origin_public_key,
              key_certificate
            )
        })

      Archethic.send_new_transaction(tx)
      handle_new_ip(tx)
    else
      :error ->
        Logger.warning("Cannot open port")

      {:error, :not_found} ->
        Logger.debug("Skip node update: Not yet bootstrapped")

      {:ok, %Node{}} ->
        Logger.debug("Skip node update: Same IP - no need to send a new node transaction")

      {:error, _} ->
        Logger.warning("Cannot fetch IP")
    end
  end

  defp open_ports do
    p2p_port = Application.get_env(:archethic, P2PListener) |> Keyword.fetch!(:port)
    web_port = Application.get_env(:archethic, WebEndpoint) |> get_in([:http, :port])

    with {:ok, _} <- PortForwarding.try_open_port(p2p_port, false),
         {:ok, _} <- PortForwarding.try_open_port(web_port, false) do
      {:ok, p2p_port, web_port}
    end
  end

  defp handle_new_ip(%Transaction{address: tx_address}) do
    nodes =
      P2P.authorized_and_available_nodes()
      |> Enum.filter(&Node.locally_available?/1)
      |> P2P.nearest_nodes()

    Utils.await_confirmation(tx_address, nodes)

    types = [:node, :oracle, :node_shared_secrets, :reward]

    Task.Supervisor.async_stream_nolink(Archethic.TaskSupervisor, types, fn type ->
      SelfRepair.resync_network_chain(type, nodes)
    end)
    |> Stream.run()
  end
end
