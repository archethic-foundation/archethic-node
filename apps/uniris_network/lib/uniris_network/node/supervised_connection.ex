defmodule UnirisNetwork.Node.SupervisedConnection do
  @moduledoc false

  @behaviour :gen_statem

  alias UnirisNetwork.Node

  require Logger

  @spec start_link(binary(), :inet.ip_address(), :inet.port_number()) :: {:ok, pid()}
  def start_link(public_key, ip, port) do
    :gen_statem.start_link(__MODULE__, [public_key, ip, port], [])
  end

  def init([public_key, ip, port]) do
    {:ok, :idle, %{ip: ip, port: port, public_key: public_key, queue: :queue.new()},
     {:next_event, :internal, :connect}}
  end

  def callback_mode do
    [:handle_event_function]
  end

  def handle_event(:internal, :connect, _, data = %{ip: ip, port: port, public_key: public_key}) do
    Logger.info("Start supervised connection for #{public_key |> Base.encode16()}")
    {:ok, pid} = p2p_client().start_link(String.to_charlist(ip), port, public_key, self())
    {:keep_state, Map.put(data, :client_pid, pid)}
  end

  def handle_event(:info, :connected, _, data = %{public_key: public_key}) do
    {:next_state, :connected, data, {:next_event, :internal, :notify_availability}}
  end

  def handle_event(:internal, :notify_availability, _, _data = %{public_key: public_key}) do
    Logger.info("Connectione established from #{public_key |> Base.encode16()}")
    Node.available(public_key)
    :keep_state_and_data
  end

  def handle_event(:internal, :notify_unavailability, _, data = %{public_key: public_key}) do
    Logger.info("Disonnection from #{public_key |> Base.encode16()}")
    Node.unavailable(public_key)
    {:keep_state, data, {:next_event, :internal, :connect}}
  end

  def handle_event(:info, {:DOWN, _ref, :process, _, _}, _, data) do
    {:next_state, :disconnected, data,
     [{:next_event, :internal, :notify_unavailability}, {:next_event, :internal, :connect}]}
  end

  def handle_event({:call, from}, {:send_message, msg}, :idle, _) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event(
        {:call, from},
        {:send_message, msg},
        :connected,
        data = %{public_key: public_key, queue: queue}
      ) do
    p2p_client().send_message(public_key, msg)
    {:keep_state, Map.put(data, :queue, :queue.in(from, queue))}
  end

  def handle_event(:info, {:p2p_response, response}, :connected, data = %{queue: queue}) do
    {{:value, client}, new_queue} = :queue.out(queue)
    new_data = Map.put(data, :queue, new_queue)

    case response do
      {:ok, data, _public_key} ->
        {:keep_state, new_data, [{:reply, client, {:ok, data}}]}

      {:error, _} ->
        {:keep_state, new_data, [{:reply, client, {:error, :invalid_payload}}]}
    end
  end

  @spec send_message(pid(), term()) :: :ok
  def send_message(pid, msg) do
    :gen_statem.call(pid, {:send_message, msg})
  end

  defp p2p_client() do
    Application.get_env(:uniris_network, :p2p_client)
  end
end
