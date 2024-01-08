defmodule Archethic.Crypto.NodeKeystore.Origin.TPMImpl do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.Crypto.ID
  alias Archethic.Crypto.NodeKeystore.Origin

  alias Archethic.Utils.PortHandler

  @behaviour Origin

  require Logger

  use GenServer
  @vsn 1

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Origin
  @spec sign_with_origin_key(data :: iodata()) :: binary()
  def sign_with_origin_key(data) do
    GenServer.call(__MODULE__, {:sign_with_origin_key, data})
  end

  @impl Origin
  @spec origin_public_key() :: Crypto.key()
  def origin_public_key do
    GenServer.call(__MODULE__, :origin_public_key)
  end

  @impl Origin
  @spec retrieve_node_seed() :: binary()
  def retrieve_node_seed do
    GenServer.call(__MODULE__, :retrieve_node_seed)
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
    %Task{ref: ref} = Task.async(fn -> request_public_key(port_handler, 0) end)
    {:noreply, Map.update!(state, :async_tasks, &Map.put(&1, ref, from))}
  end

  def handle_call({:sign_with_origin_key, data}, from, state = %{port_handler: port_handler}) do
    %Task{ref: ref} = Task.async(fn -> sign(port_handler, 0, data) end)
    {:noreply, Map.update!(state, :async_tasks, &Map.put(&1, ref, from))}
  end

  def handle_call(:retrieve_node_seed, _from, state = %{port_handler: port_handler}) do
    {:reply, retrieve_node_seed(port_handler), state}
  end

  @impl GenServer
  def handle_info({ref, result}, state = %{async_tasks: async_tasks}) do
    case Map.pop(async_tasks, ref) do
      {nil, async_tasks} ->
        Logger.warning("Async task not found for the TPM impl")
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
    # Set TPM root key and key index at 0th
    # Generate the node seed
    PortHandler.request(port_handler, 1, <<0::16>>)
  end

  defp retrieve_node_seed(port_handler) do
    {:ok, seed} = PortHandler.request(port_handler, 4, <<>>)
    seed
  end
end
