defmodule UnirisP2P.DefaultImpl.SupervisedConnection do
  @moduledoc false

  @behaviour :gen_statem

  alias UnirisP2P.Node
  alias UnirisP2P.ConnectionRegistry
  alias __MODULE__.Client, as: P2PClient

  require Logger

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @spec start_link(
          ip: :inet.ip_address(),
          port: :inet.port_number(),
          public_key: UnirisCrypto.key()
        ) ::
          {:ok, pid()}
  def start_link(opts) do
    ip = Keyword.get(opts, :ip)
    port = Keyword.get(opts, :port)
    public_key = Keyword.get(opts, :public_key)
    :gen_statem.start_link(via_tuple(public_key), __MODULE__, [ip, port, public_key], [])
  end

  def init([ip, port, public_key]) do
    {:ok, pid} = P2PClient.start_link(ip, port, self())
    Logger.info("Initialize P2P connection with #{inspect(ip)}:#{port}")
    {:ok, :idle, %{ip: ip, port: port, public_key: public_key, client_pid: pid}}
  end

  def callback_mode do
    [:handle_event_function]
  end

  def handle_event(:info, :connected, _, data = %{public_key: public_key, }) do
    Node.available(public_key)
    {:next_state, :connected, data}
  end

  def handle_event(:info, :disconnected, _, data = %{public_key: public_key}) do
    Node.unavailable(public_key)
    {:next_state, :disconnected, data}
  end

  def handle_event(
        {:call, from},
        {:send_message, msg},
        :connected,
        %{client_pid: pid}
      ) do
    {:ok, result} = P2PClient.send_message(pid, msg)
    {:keep_state_and_data, {:reply, from, result}}
  end

  def handle_event({:call, _from}, {:send_message, _msg}, _, _) do
    {:keep_state_and_data, :postpone}
  end

  def terminate(_reason, _, %{client_pid: client_pid}) do
    Process.exit(client_pid, :shutdown)
    :ok
  end

  @spec send_message(node_public_key :: UnirisCrypto.key(), message :: term()) ::
          response :: term()
  def send_message(public_key, msg) do
    :gen_statem.call(via_tuple(public_key), {:send_message, msg})
  end

  defp via_tuple(public_key) do
    {:via, Registry, {ConnectionRegistry, public_key}}
  end
end
