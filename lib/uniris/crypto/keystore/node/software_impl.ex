defmodule Uniris.Crypto.NodeKeystore.SoftwareImpl do
  @moduledoc false

  use GenServer

  alias Uniris.Crypto
  alias Uniris.Crypto.Ed25519
  alias Uniris.Crypto.ID
  alias Uniris.Crypto.KeystoreCounter
  alias Uniris.Crypto.NodeKeystoreImpl

  require Logger

  @behaviour NodeKeystoreImpl

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl NodeKeystoreImpl
  def sign_with_node_key(data) do
    GenServer.call(__MODULE__, {:sign_with_node_key, data})
  end

  @impl NodeKeystoreImpl
  def sign_with_node_key(data, index) do
    GenServer.call(__MODULE__, {:sign_with_node_key, data, index})
  end

  @impl NodeKeystoreImpl
  def node_public_key do
    GenServer.call(__MODULE__, :node_public_key)
  end

  @impl NodeKeystoreImpl
  def node_public_key(index) do
    GenServer.call(__MODULE__, {:node_public_key, index})
  end

  @impl NodeKeystoreImpl
  def diffie_hellman(public_key) do
    GenServer.call(__MODULE__, {:diffie_hellman, public_key})
  end

  @impl GenServer
  def init(opts) do
    seed = Keyword.fetch!(opts, :seed)
    {:ok, %{node_seed: seed}}
  end

  @impl GenServer
  def handle_call(
        {:sign_with_node_key, data},
        _,
        state = %{node_seed: seed}
      ) do
    index = KeystoreCounter.get_node_key_counter()
    {_, pv} = previous_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call({:sign_with_node_key, data, index}, _, state = %{node_seed: seed}) do
    {_, pv} = Crypto.derive_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call(:node_public_key, _, state = %{node_seed: seed}) do
    index = KeystoreCounter.get_node_key_counter()
    {pub, _} = previous_keypair(seed, index)
    {:reply, pub, state}
  end

  def handle_call({:node_public_key, index}, _, state = %{node_seed: seed}) do
    {pub, _} = Crypto.derive_keypair(seed, index)
    {:reply, pub, state}
  end

  def handle_call({:diffie_hellman, public_key}, _, state = %{node_seed: seed}) do
    index = KeystoreCounter.get_node_key_counter()
    {_, <<curve_id::8, pv::binary>>} = previous_keypair(seed, index)

    shared_secret =
      case ID.to_curve(curve_id) do
        :ed25519 ->
          x25519_sk = Ed25519.convert_to_x25519_private_key(pv)
          :crypto.compute_key(:ecdh, public_key, x25519_sk, :x25519)

        curve ->
          :crypto.compute_key(:ecdh, public_key, pv, curve)
      end

    {:reply, shared_secret, state}
  end

  defp previous_keypair(seed, 0) do
    Crypto.derive_keypair(seed, 0)
  end

  defp previous_keypair(seed, index) do
    Crypto.derive_keypair(seed, index - 1)
  end
end
