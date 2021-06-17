defmodule Uniris.Crypto.NodeKeystore.TPMImpl do
  @moduledoc false

  alias Uniris.Crypto
  alias Uniris.Crypto.ID
  alias Uniris.Crypto.NodeKeystoreImpl

  alias Uniris.TransactionChain

  alias Uniris.Utils.PortHandler

  @behaviour NodeKeystoreImpl

  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl NodeKeystoreImpl
  @spec sign_with_first_key(data :: binary()) :: binary()
  def sign_with_first_key(data) when is_binary(data) do
    GenServer.call(__MODULE__, {:sign_with_first_key, data})
  end

  @impl NodeKeystoreImpl
  @spec sign_with_last_key(data :: binary()) :: binary()
  def sign_with_last_key(data) when is_binary(data) do
    GenServer.call(__MODULE__, {:sign_with_last_key, data})
  end

  @impl NodeKeystoreImpl
  @spec last_public_key() :: Crypto.key()
  def last_public_key do
    GenServer.call(__MODULE__, :get_last_public_key) |> ID.prepend_key(:secp256r1, :tpm)
  end

  @impl NodeKeystoreImpl
  @spec first_public_key() :: Crypto.key()
  def first_public_key do
    GenServer.call(__MODULE__, :get_first_public_key) |> ID.prepend_key(:secp256r1, :tpm)
  end

  @impl NodeKeystoreImpl
  @spec next_public_key() :: Crypto.key()
  def next_public_key do
    GenServer.call(__MODULE__, :get_next_public_key) |> ID.prepend_key(:secp256r1, :tpm)
  end

  @impl NodeKeystoreImpl
  @spec diffie_hellman(public_key :: Crypto.key()) :: binary()
  def diffie_hellman(public_key) when is_binary(public_key) do
    GenServer.call(__MODULE__, {:diffie_hellman, public_key})
  end

  @impl NodeKeystoreImpl
  @spec persist_next_keypair() :: :ok
  def persist_next_keypair do
    GenServer.call(__MODULE__, :persist_next_keypair)
  end

  @impl GenServer
  def init(_) do
    tpm_program = Application.app_dir(:uniris, "priv/c_dist/tpm")
    {:ok, port_handler} = PortHandler.start_link(program: tpm_program)
    {:ok, %{index: 0, port_handler: port_handler}, {:continue, :initialize_tpm}}
  end

  @impl GenServer
  def handle_continue(:initialize_tpm, state = %{port_handler: port_handler}) do
    first_public_key = request_public_key(port_handler, 0)

    nb_keys =
      first_public_key
      |> Crypto.hash()
      |> TransactionChain.get_last_address()
      |> TransactionChain.size()

    last_public_key = get_last_public_key(port_handler, nb_keys)

    next_public_key = request_public_key(port_handler, nb_keys + 1)
    set_index(port_handler, nb_keys)

    new_state =
      state
      |> Map.put(:first_public_key, first_public_key)
      |> Map.put(:last_public_key, last_public_key)
      |> Map.put(:next_public_key, next_public_key)
      |> Map.put(:index, nb_keys)

    {:noreply, new_state}
  end

  defp get_last_public_key(port_handler, nb_keys) when nb_keys > 0 do
    request_public_key(port_handler, nb_keys - 1)
  end

  defp get_last_public_key(port_handler, 0), do: request_public_key(port_handler, 0)

  @impl GenServer
  def handle_call({:sign_with_first_key, data}, _, state = %{port_handler: port_handler}) do
    sig = sign(port_handler, 0, data)
    {:reply, sig, state}
  end

  def handle_call(
        {:sign_with_last_key, data},
        _,
        state = %{port_handler: port_handler, index: index}
      ) do
    sig = sign(port_handler, index, data)
    {:reply, sig, state}
  end

  def handle_call(:get_last_public_key, _, state = %{last_public_key: last_public_key}) do
    {:reply, last_public_key, state}
  end

  def handle_call(:get_first_public_key, _, state = %{first_public_key: first_public_key}) do
    {:reply, first_public_key, state}
  end

  def handle_call(:get_next_public_key, _, state = %{next_public_key: next_public_key}) do
    {:reply, next_public_key, state}
  end

  def handle_call(:persist_next_keypair, _, state = %{index: index, port_handler: port_handler}) do
    :ok = PortHandler.request(port_handler, 5, <<index + 1::16>>)
    {:reply, :ok, Map.update!(state, :index, &(&1 + 1))}
  end

  def handle_call(
        {:diffile_hellman, public_key},
        _,
        state = %{index: index, port_handler: port_handler}
      ) do
    {:ok, shared_key} = PortHandler.request(port_handler, 6, <<index::16, public_key::binary>>)
    {:reply, shared_key, state}
  end

  defp request_public_key(port_handler, index) do
    {:ok, <<_::16, public_key::binary>>} = PortHandler.request(port_handler, 2, <<index::16>>)
    public_key
  end

  defp set_index(port_handler, index) do
    :ok = PortHandler.request(port_handler, 1, <<index::16>>)
  end

  defp sign(port_handler, index, data) do
    hash = :crypto.hash(:sha256, data)
    {:ok, sig} = PortHandler.request(port_handler, 3, <<index::16, hash::binary>>)
    sig
  end
end
