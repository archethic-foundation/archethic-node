defmodule Archethic.Crypto.NodeKeystore.SoftwareImpl do
  @moduledoc false

  use GenServer

  alias Archethic.Crypto
  alias Archethic.Crypto.NodeKeystore

  @behaviour NodeKeystore

  def start_link(arg \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, arg, opts)
  end

  @impl NodeKeystore
  def sign_with_origin_key(pid \\ __MODULE__, data) do
    GenServer.call(pid, {:sign_with_origin_key, data})
  end

  @impl NodeKeystore
  def origin_public_key(pid \\ __MODULE__) do
    GenServer.call(pid, :origin_public_key)
  end

  @impl GenServer
  def init(_arg \\ []) do
    {:ok,
     %{
       origin_keypair: Crypto.generate_deterministic_keypair(:crypto.strong_rand_bytes(32))
     }}
  end

  @impl GenServer
  def handle_call({:sign_with_origin_key, data}, _, state = %{origin_keypair: {_, pv}}) do
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call(:origin_public_key, _, state = %{origin_keypair: {pub, _}}) do
    {:reply, pub, state}
  end
end
