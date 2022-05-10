defmodule Archethic.Crypto.NodeKeystore.TPMImpl do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.Crypto.ID
  alias Archethic.Crypto.NodeKeystore

  alias Archethic.Utils.PortHandler

  @behaviour NodeKeystore

  require Logger

  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl NodeKeystore
  @spec sign_with_origin_key(data :: iodata()) :: binary()
  def sign_with_origin_key(data) do
    GenServer.call(__MODULE__, {:sign_with_origin_key, data})
  end

  @impl NodeKeystore
  @spec origin_public_key() :: Crypto.key()
  def origin_public_key do
    GenServer.call(__MODULE__, :origin_public_key)
  end

  @impl GenServer
  def init(_) do
    tpm_program = Application.app_dir(:archethic, "priv/c_dist/tpm_port")
    {:ok, port_handler} = PortHandler.start_link(program: tpm_program)

    Process.monitor(port_handler)

    initialize_tpm(port_handler)

    {:ok, %{program: tpm_program, port_handler: port_handler, async_tasks: %{}}}
  end

  @impl GenServer
  def handle_call(:origin_public_key, from, state = %{port_handler: port_handler}) do
    t = Task.async(fn -> request_public_key(port_handler, 0) end)
    {:noreply, Map.update!(state, :async_tasks, &Map.put(&1, t, from))}
  end

  def handle_call({:sign_with_origin_key, data}, from, state = %{port_handler: port_handler}) do
    t = Task.async(fn -> sign(port_handler, 0, data) end)
    {:noreply, Map.update!(state, :async_tasks, &Map.put(&1, t, from))}
  end

  @impl GenServer
  def handle_info({ref, result}, state = %{async_tasks: async_tasks}) do
    case Map.pop(async_tasks, ref) do
      {nil, async_tasks} ->
        {:noreply, %{state | async_tasks: async_tasks}}

      {from, async_tasks} ->
        GenServer.reply(from, result)
        {:noreply, %{state | async_tasks: async_tasks}}
    end
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, _},
        state = %{program: tpm_program, port_handler: pid}
      ) do
    {:ok, port_handler} = PortHandler.start_link(program: tpm_program)
    Process.monitor(port_handler)
    {:noreply, %{state | port_handler: port_handler}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  defp request_public_key(port_handler, index) do
    {:ok, <<_::binary-size(26), public_key::binary>>} =
      PortHandler.request(port_handler, 2, <<index::16>>)

    ID.prepend_key(public_key, :secp256r1, :tpm)
  end

  defp set_index(port_handler, index) do
    :ok = PortHandler.request(port_handler, 5, <<index::16>>)
  end

  defp sign(port_handler, index, data) do
    hash = :crypto.hash(:sha256, data)
    start = System.monotonic_time()
    {:ok, sig} = PortHandler.request(port_handler, 3, <<index::16, hash::binary>>)

    :telemetry.execute([:archethic, :crypto, :tpm_sign], %{
      duration: System.monotonic_time() - start
    })

    sig
  end

  defp initialize_tpm(port_handler) do
    set_index(port_handler, 0)
  end
end
