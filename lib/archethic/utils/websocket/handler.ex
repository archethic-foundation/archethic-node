defmodule Archethic.Utils.WebSocket.SocketHandler do
  @moduledoc """
   Genserver with WebSockex to handle websocket (for absinthe subscription)
  """
  use WebSockex
  require Logger

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
    protocol = Keyword.get(opts, :protocol, "ws")

    ws_url = "#{protocol}://#{host}:#{port}/socket/websocket"

    state = %{
      subscriptions: %{},
      queries: %{},
      msg_ref: 0,
      heartbeat_timer: nil,
      socket: name
    }

    WebSockex.start_link(ws_url, __MODULE__, state,
      handle_initial_conn_failure: true,
      async: true,
      name: name
    )
  end

  def query(socket, client_pid, ref, query, variables \\ []) do
    WebSockex.cast(socket, {:query, {client_pid, ref, query, variables}})
  end

  def subscribe(socket, client_pid, local_subscription_id, query, variables \\ []) do
    WebSockex.cast(socket, {:subscribe, {client_pid, local_subscription_id, query, variables}})
  end

  @impl WebSockex
  def handle_connect(_conn, state = %{socket: socket}) do
    WebSockex.cast(socket, :join)

    # Send a heartbeat
    heartbeat_timer = Process.send_after(self(), :heartbeat, @heartbeat_sleep)
    state = Map.put(state, :heartbeat_timer, heartbeat_timer)

    {:ok, state}
  end

  @impl WebSockex
  def handle_disconnect(map, state = %{heartbeat_timer: heartbeat_timer}) do
    Logger.error("#{__MODULE__} - Disconnected: #{inspect(map)}")

    if heartbeat_timer do
      :timer.cancel(heartbeat_timer)
    end

    state = Map.put(state, :heartbeat_timer, nil)

    :timer.sleep(@disconnect_sleep)

    {:reconnect, state}
  end

  @impl WebSockex
  def handle_info(:heartbeat, state = %{socket: socket}) do
    WebSockex.cast(socket, :heartbeat)

    # Send another heartbeat
    heartbeat_timer = Process.send_after(self(), :heartbeat, @heartbeat_sleep)
    state = Map.put(state, :heartbeat_timer, heartbeat_timer)

    {:ok, state}
  end

  def handle_info(msg, state) do
    Logger.info("#{__MODULE__} Info - Message: #{inspect(msg)}")

    {:ok, state}
  end

  @impl WebSockex
  def handle_cast(:join, state = %{msg_ref: msg_ref}) do
    msg =
      %{
        topic: "__absinthe__:control",
        event: "phx_join",
        payload: %{},
        ref: msg_ref
      }
      |> Jason.encode!()

    new_state =
      state
      |> Map.update!(:queries, &Map.put(&1, msg_ref, :join))
      |> Map.update!(:msg_ref, &(&1 + 1))

    {:reply, {:text, msg}, new_state}
  end

  def handle_cast(:heartbeat, state = %{msg_ref: msg_ref}) do
    msg =
      %{
        topic: "phoenix",
        event: "heartbeat",
        payload: %{},
        ref: msg_ref
      }
      |> Jason.encode!()

    new_state =
      state
      |> Map.update!(:queries, &Map.put(&1, msg_ref, :hearbeat))
      |> Map.update!(:msg_ref, &(&1 + 1))

    {:reply, {:text, msg}, new_state}
  end

  def handle_cast(
        {:query, {client_pid, ref, query, variables}},
        state = %{msg_ref: msg_ref}
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
      |> Jason.encode!()

    new_state =
      state
      |> Map.update!(:queries, &Map.put(&1, msg_ref, {:query, client_pid, ref}))
      |> Map.update!(:msg_ref, &(&1 + 1))

    {:reply, {:text, msg}, new_state}
  end

  def handle_cast(
        {:subscribe, {client_pid, local_subscription_id, query, variables}},
        state = %{msg_ref: msg_ref}
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
      |> Jason.encode!()

    new_state =
      state
      |> Map.update!(
        :queries,
        &Map.put(&1, msg_ref, {:subscribe, client_pid, local_subscription_id})
      )
      |> Map.update!(:msg_ref, &(&1 + 1))

    {:reply, {:text, msg}, new_state}
  end

  def handle_cast(message, state) do
    Logger.info("#{__MODULE__} - Cast: #{inspect(message)}")
    super(message, state)
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    msg
    |> Jason.decode!()
    |> handle_msg(state)
  end

  defp handle_msg(%{"event" => "phx_reply", "payload" => payload, "ref" => msg_ref}, state) do
    queries = state.queries
    {command, queries} = Map.pop(queries, msg_ref)
    state = Map.put(state, :queries, queries)

    status = payload["status"] |> String.to_atom()

    state =
      case command do
        {:query, client_pid, ref} ->
          phx_event({:query, client_pid, ref}, status, payload, state)

        {:subscribe, client_pid, local_subscription_id} ->
          phx_event({:subscribe, client_pid, local_subscription_id}, status, payload, state)

        :join ->
          phx_event(:join, status, payload, state)

        :heartbeat ->
          phx_event(:heartbeat, status, payload, state)
      end

    {:ok, state}
  end

  defp handle_msg(
         %{
           "event" => "subscription:data",
           "payload" => %{"result" => %{"data" => data}},
           "topic" => subscription_id
         },
         state = %{subscriptions: subscriptions}
       ) do
    {client_pid, _local_subscription_id} = Map.get(subscriptions, subscription_id)

    send(client_pid, data)

    {:ok, state}
  end

  defp handle_msg(msg, state) do
    Logger.info("#{__MODULE__} - Msg: #{inspect(msg)}")

    {:ok, state}
  end

  defp phx_event({:query, client_pid, _ref}, :ok, payload, state) do
    data = payload["response"]["data"]
    send(client_pid, {:ok, data})
    state
  end

  defp phx_event({:query, client_pid, _ref}, :error, payload, state) do
    errors = payload["response"]["errors"]
    send(client_pid, {:error, errors})
    state
  end

  defp phx_event({:subscribe, client_pid, local_subscription_id}, :ok, payload, state) do
    subscription_id = payload["response"]["subscriptionId"]

    Map.update!(
      state,
      :subscriptions,
      &Map.put(&1, subscription_id, {client_pid, local_subscription_id})
    )
  end

  defp phx_event({:subscribe, _client_pid, _local_subscription_id}, :error, payload, _state) do
    raise "Subscription Error - #{inspect(payload)}"
  end

  defp phx_event(:join, :ok, _payload, state), do: state

  defp phx_event(:join, :error, payload, _state) do
    raise "Join Error - #{inspect(payload)}"
  end

  defp phx_event(:heartbeat, :ok, _payload, state), do: state

  defp phx_event(:heartbeat, :error, payload, _state) do
    raise "Heartbeat Error - #{inspect(payload)}"
  end
end
