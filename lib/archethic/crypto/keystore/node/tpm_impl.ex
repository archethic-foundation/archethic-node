defmodule ArchEthic.Crypto.NodeKeystore.TPMImpl do
  @moduledoc false

  alias ArchEthic.Crypto
  alias ArchEthic.Crypto.ID
  alias ArchEthic.Crypto.NodeKeystore

  alias ArchEthic.TransactionChain

  alias ArchEthic.Utils.PortHandler

  @behaviour NodeKeystore

  require Logger

  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl NodeKeystore
  @spec sign_with_first_key(data :: iodata()) :: binary()
  def sign_with_first_key(data) do
    GenServer.call(__MODULE__, {:sign_with_first_key, data})
  end

  @impl NodeKeystore
  @spec sign_with_last_key(data :: iodata()) :: binary()
  def sign_with_last_key(data) do
    GenServer.call(__MODULE__, {:sign_with_last_key, data})
  end

  @impl NodeKeystore
  @spec sign_with_previous_key(data :: iodata()) :: binary()
  def sign_with_previous_key(data) do
    GenServer.call(__MODULE__, {:sign_with_previous_key, data})
  end

  @impl NodeKeystore
  @spec last_public_key() :: Crypto.key()
  def last_public_key do
    GenServer.call(__MODULE__, :get_last_public_key) |> ID.prepend_key(:secp256r1, :tpm)
  end

  @impl NodeKeystore
  @spec first_public_key() :: Crypto.key()
  def first_public_key do
    GenServer.call(__MODULE__, :get_first_public_key) |> ID.prepend_key(:secp256r1, :tpm)
  end

  @impl NodeKeystore
  @spec previous_public_key() :: Crypto.key()
  def previous_public_key do
    GenServer.call(__MODULE__, :get_previous_public_key) |> ID.prepend_key(:secp256r1, :tpm)
  end

  @impl NodeKeystore
  @spec next_public_key() :: Crypto.key()
  def next_public_key do
    GenServer.call(__MODULE__, :get_next_public_key) |> ID.prepend_key(:secp256r1, :tpm)
  end

  @impl NodeKeystore
  @spec diffie_hellman(public_key :: Crypto.key()) :: binary()
  def diffie_hellman(public_key) when is_binary(public_key) do
    GenServer.call(__MODULE__, {:diffie_hellman, public_key})
  end

  @impl NodeKeystore
  @spec persist_next_keypair() :: :ok
  def persist_next_keypair do
    GenServer.call(__MODULE__, :persist_next_keypair)
  end

  @impl GenServer
  def init(_) do
    tpm_program = Application.app_dir(:archethic, "priv/c_dist/tpm_port")
    {:ok, port_handler} = PortHandler.start_link(program: tpm_program)
    {:ok, %{index: 0, port_handler: port_handler}, {:continue, :initialize_tpm}}
  end

  @impl GenServer
  def handle_continue(:initialize_tpm, state = %{port_handler: port_handler}) do
    initialize_tpm(port_handler, 0)

    first_public_key = request_public_key(port_handler, 0)

    nb_keys =
      first_public_key
      |> Crypto.hash()
      |> TransactionChain.get_last_address()
      |> TransactionChain.size()

    Logger.info("Start NodeKeystore at #{nb_keys}th key")

    last_index =
      if nb_keys > 0 do
        nb_keys - 1
      else
        nb_keys
      end

    last_public_key = request_public_key(port_handler, last_index)

    previous_public_key = request_public_key(port_handler, nb_keys)

    next_public_key = request_public_key(port_handler, nb_keys + 1)
    set_index(port_handler, nb_keys)

    new_state =
      state
      |> Map.put(:first_public_key, first_public_key)
      |> Map.put(:last_public_key, last_public_key)
      |> Map.put(:previous_public_key, previous_public_key)
      |> Map.put(:next_public_key, next_public_key)
      |> Map.put(:next_index, nb_keys + 1)
      |> Map.put(:last_index, last_index)
      |> Map.put(:prev_index, nb_keys)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call({:sign_with_first_key, data}, _, state = %{port_handler: port_handler}) do
    sig = sign(port_handler, 0, data)
    {:reply, sig, state}
  end

  def handle_call(
        {:sign_with_last_key, data},
        _,
        state = %{port_handler: port_handler, last_index: index}
      ) do
    sig = sign(port_handler, index, data)
    {:reply, sig, state}
  end

  def handle_call(
        {:sign_with_previous_key, data},
        _,
        state = %{port_handler: port_handler, prev_index: index}
      ) do
    sig = sign(port_handler, index, data)
    {:reply, sig, state}
  end

  def handle_call(:get_last_public_key, _, state = %{last_public_key: public_key}) do
    {:reply, public_key, state}
  end

  def handle_call(:get_first_public_key, _, state = %{first_public_key: public_key}) do
    {:reply, public_key, state}
  end

  def handle_call(:get_previous_public_key, _, state = %{previous_public_key: public_key}) do
    {:reply, public_key, state}
  end

  def handle_call(:get_next_public_key, _, state = %{next_public_key: public_key}) do
    {:reply, public_key, state}
  end

  def handle_call(:persist_next_keypair, _, state = %{index: index, port_handler: port_handler}) do
    :ok = PortHandler.request(port_handler, 5, <<index + 1::16>>)
    {:reply, :ok, Map.update!(state, :index, &(&1 + 1))}
  end

  def handle_call(
        {:diffie_hellman, public_key},
        _,
        state = %{last_index: index, port_handler: port_handler}
      ) do
    {:ok, <<_header::binary-size(1), z_x::binary-size(32), _z_y::binary-size(32)>>} =
      PortHandler.request(port_handler, 6, <<index::16, public_key::binary>>)

    {:reply, z_x, state}
  end

  defp request_public_key(port_handler, index) do
    {:ok, <<_::binary-size(26), public_key::binary>>} =
      PortHandler.request(port_handler, 2, <<index::16>>)

    public_key
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

  defp initialize_tpm(port_handler, index) do
    PortHandler.request(port_handler, 1, <<index::16>>)
  end
end
