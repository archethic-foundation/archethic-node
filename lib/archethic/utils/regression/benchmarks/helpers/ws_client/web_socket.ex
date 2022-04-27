defmodule ArchEthic.Utils.Regression.Benchmarks.Helpers.WSClient.WebSocket do
  @moduledoc """
   Genserver with WebSockex to handle websocket (for absinthe subscription)
  """
  use WebSockex
  require Logger
  alias ArchEthic.Utils.Regression.Benchmarks.Helpers.WSClient.SubscriptionServer

  @heartbeat_sleep 15_000
  @disconnect_sleep 15_000

  # ref:
  # Heartbeat: http://graemehill.ca/websocket-clients-and-phoenix-channels/
  # https://stackoverflow.com/questions/34948331/how-to-implement-a-resetable-countdown-timer-with-a-genserver-in-elixir-or-erlan
  # https://github.com/annkissam/absinthe_websocket/blob/master/lib/absinthe_websocket/websocket.ex

  def start_link(opts) do
    name = Keyword.get(opts, :ws_name, __MODULE__)
    host = Keyword.get(opts, :host, "localhost")
    port = Keyword.get(opts, :port, "4000")

    ws_url = "ws://#{host}:#{port}/socket/websocket"

    state = %{
      subscriptions: %{},
      queries: %{},
      msg_ref: 0,
      heartbeat_timer: nil,
      socket: name,
      subscription_server: SubscriptionServer
    }

    WebSockex.start_link(ws_url, __MODULE__, state,
      handle_initial_conn_failure: true,
      async: true,
      name: name
    )
  end

  def query(socket, pid, ref, query, variables \\ []) do
    WebSockex.cast(socket, {:query, {pid, ref, query, variables}})
  end

  def subscribe(socket, pid, local_subscription_id, query, variables \\ []) do
    WebSockex.cast(socket, {:subscribe, {pid, local_subscription_id, query, variables}})
  end

  def handle_connect(_conn, %{socket: socket} = state) do
    # Logger.info "#{__MODULE__} - Connected: #{inspect conn}"

    WebSockex.cast(socket, {:join})

    # Send a heartbeat
    heartbeat_timer = Process.send_after(self(), :heartbeat, @heartbeat_sleep)
    state = Map.put(state, :heartbeat_timer, heartbeat_timer)

    {:ok, state}
  end

  def handle_disconnect(map, %{heartbeat_timer: heartbeat_timer} = state) do
    Logger.error("#{__MODULE__} - Disconnected: #{inspect(map)}")

    if heartbeat_timer do
      :timer.cancel(heartbeat_timer)
    end

    state = Map.put(state, :heartbeat_timer, nil)

    :timer.sleep(@disconnect_sleep)

    {:reconnect, state}
  end

  def handle_info(:heartbeat, %{socket: socket} = state) do
    WebSockex.cast(socket, {:heartbeat})

    # Send another heartbeat
    heartbeat_timer = Process.send_after(self(), :heartbeat, @heartbeat_sleep)
    state = Map.put(state, :heartbeat_timer, heartbeat_timer)

    {:ok, state}
  end

  def handle_info(msg, state) do
    Logger.info("#{__MODULE__} Info - Message: #{inspect(msg)}")

    {:ok, state}
  end

  def handle_cast({:join}, %{queries: queries, msg_ref: msg_ref} = state) do
    msg =
      %{
        topic: "__absinthe__:control",
        event: "phx_join",
        payload: %{},
        ref: msg_ref
      }
      |> Poison.encode!()

    queries = Map.put(queries, msg_ref, {:join})

    state =
      state
      |> Map.put(:queries, queries)
      |> Map.put(:msg_ref, msg_ref + 1)

    {:reply, {:text, msg}, state}
  end

  def handle_cast({:heartbeat}, %{queries: queries, msg_ref: msg_ref} = state) do
    msg =
      %{
        topic: "phoenix",
        event: "heartbeat",
        payload: %{},
        ref: msg_ref
      }
      |> Poison.encode!()

    queries = Map.put(queries, msg_ref, {:heartbeat})

    state =
      state
      |> Map.put(:queries, queries)
      |> Map.put(:msg_ref, msg_ref + 1)

    {:reply, {:text, msg}, state}
  end

  def handle_cast(
        {:query, {pid, ref, query, variables}},
        %{queries: queries, msg_ref: msg_ref} = state
      ) do
    doc = %{
      "query" => query,
      "variables" => variables
    }

    msg =
      %{
        topic: "__absinthe__:control",
        event: "doc",
        payload: doc,
        ref: msg_ref
      }
      |> Poison.encode!()

    queries = Map.put(queries, msg_ref, {:query, pid, ref})

    state =
      state
      |> Map.put(:queries, queries)
      |> Map.put(:msg_ref, msg_ref + 1)

    {:reply, {:text, msg}, state}
  end

  def handle_cast(
        {:subscribe, {pid, local_subscription_id, query, variables}},
        %{queries: queries, msg_ref: msg_ref} = state
      ) do
    doc = %{
      "query" => query,
      "variables" => variables
    }

    msg =
      %{
        topic: "__absinthe__:control",
        event: "doc",
        payload: doc,
        ref: msg_ref
      }
      |> Poison.encode!()

    queries = Map.put(queries, msg_ref, {:subscribe, pid, local_subscription_id})

    state =
      state
      |> Map.put(:queries, queries)
      |> Map.put(:msg_ref, msg_ref + 1)

    {:reply, {:text, msg}, state}
  end

  def handle_cast(message, state) do
    Logger.info("#{__MODULE__} - Cast: #{inspect(message)}")

    super(message, state)
  end

  def handle_frame({:text, msg}, state) do
    msg =
      msg
      |> Poison.decode!()

    handle_msg(msg, state)
  end

  def handle_msg(%{"event" => "phx_reply", "payload" => payload, "ref" => msg_ref}, state) do
    # Logger.info "#{__MODULE__} - Reply: #{inspect msg}"

    queries = state.queries
    {command, queries} = Map.pop(queries, msg_ref)
    state = Map.put(state, :queries, queries)

    status = payload["status"] |> String.to_atom()

    state =
      case command do
        {:query, pid, ref} ->
          case status do
            :ok ->
              data = payload["response"]["data"]
              GenServer.cast(pid, {:query_response, ref, {status, data}})

            :error ->
              errors = payload["response"]["errors"]
              GenServer.cast(pid, {:query_response, ref, {status, errors}})
          end

          state

        {:subscribe, pid, local_subscription_id} ->
          unless status == :ok do
            raise "Subscription Error - #{inspect(payload)}"
          end

          subscription_id = payload["response"]["subscriptionId"]

          subscriptions =
            Map.put(state.subscriptions, subscription_id, {pid, local_subscription_id})

          Map.put(state, :subscriptions, subscriptions)

        {:join} ->
          unless status == :ok do
            raise "Join Error - #{inspect(payload)}"
          end

          GenServer.cast(state.subscription_server, {:joined})

          state

        {:heartbeat} ->
          unless status == :ok do
            raise "Heartbeat Error - #{inspect(payload)}"
          end

          state
      end

    {:ok, state}
  end

  def handle_msg(
        %{"event" => "subscription:data", "payload" => payload, "topic" => subscription_id},
        %{subscriptions: subscriptions} = state
      ) do
    {pid, local_subscription_id} = Map.get(subscriptions, subscription_id)

    data = payload["result"]["data"]

    GenServer.cast(pid, {:subscription, local_subscription_id, data})

    {:ok, state}
  end

  def handle_msg(msg, state) do
    Logger.info("#{__MODULE__} - Msg: #{inspect(msg)}")

    {:ok, state}
  end
end
