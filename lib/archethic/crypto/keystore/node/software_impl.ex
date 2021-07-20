defmodule ArchEthic.Crypto.NodeKeystore.SoftwareImpl do
  @moduledoc false

  use GenServer

  alias ArchEthic.Crypto
  alias ArchEthic.Crypto.Ed25519
  alias ArchEthic.Crypto.ID
  alias ArchEthic.Crypto.NodeKeystore

  alias ArchEthic.Utils

  require Logger

  @behaviour NodeKeystore

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl NodeKeystore
  def sign_with_first_key(data) do
    GenServer.call(__MODULE__, {:sign_with_first_key, data})
  end

  @impl NodeKeystore
  def sign_with_last_key(data) do
    GenServer.call(__MODULE__, {:sign_with_last_key, data})
  end

  @impl NodeKeystore
  def sign_with_previous_key(data) do
    GenServer.call(__MODULE__, {:sign_with_previous_key, data})
  end

  @impl NodeKeystore
  def last_public_key do
    GenServer.call(__MODULE__, :last_public_key)
  end

  @impl NodeKeystore
  def first_public_key do
    GenServer.call(__MODULE__, :first_public_key)
  end

  @impl NodeKeystore
  def previous_public_key do
    GenServer.call(__MODULE__, :previous_public_key)
  end

  @impl NodeKeystore
  def next_public_key do
    GenServer.call(__MODULE__, :next_public_key)
  end

  @impl NodeKeystore
  def diffie_hellman_with_first_key(public_key) do
    GenServer.call(__MODULE__, {:diffie_hellman_first, public_key})
  end

  @impl NodeKeystore
  def diffie_hellman_with_last_key(public_key) do
    GenServer.call(__MODULE__, {:diffie_hellman_last, public_key})
  end

  @impl NodeKeystore
  def persist_next_keypair do
    GenServer.cast(__MODULE__, :persist_next_keypair)
  end

  @impl GenServer
  def init(opts) do
    seed = Keyword.fetch!(opts, :seed)
    first_keypair = Crypto.derive_keypair(seed, 0)

    nb_keys =
      case File.read(Utils.mut_dir("crypto/index")) do
        {:ok, index} ->
          String.to_integer(index)

        _ ->
          0
      end

    Logger.info("Start NodeKeystore at #{nb_keys}th key")

    last_keypair =
      if nb_keys == 0 do
        first_keypair
      else
        Crypto.derive_keypair(seed, nb_keys - 1)
      end

    previous_keypair = Crypto.derive_keypair(seed, nb_keys)

    next_keypair = Crypto.derive_keypair(seed, nb_keys + 1)

    Logger.info("Next public key will be #{Base.encode16(elem(next_keypair, 0))}")
    Logger.info("Previous public key will be #{Base.encode16(elem(previous_keypair, 0))}")
    Logger.info("Publication/Last public key will be #{Base.encode16(elem(last_keypair, 0))}")

    {:ok,
     %{
       first_keypair: first_keypair,
       previous_keypair: previous_keypair,
       last_keypair: last_keypair,
       next_keypair: next_keypair,
       index: nb_keys,
       seed: seed
     }}
  end

  @impl GenServer
  def handle_call(
        {:sign_with_first_key, data},
        _,
        state = %{first_keypair: {_, pv}}
      ) do
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call(
        {:sign_with_last_key, data},
        _,
        state = %{last_keypair: {_, pv}}
      ) do
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call({:sign_with_previous_key, data}, _, state = %{previous_keypair: {_, pv}}) do
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call(:first_public_key, _, state = %{first_keypair: {pub, _}}) do
    {:reply, pub, state}
  end

  def handle_call(:last_public_key, _, state = %{last_keypair: {pub, _}}) do
    {:reply, pub, state}
  end

  def handle_call(:previous_public_key, _, state = %{previous_keypair: {pub, _}}) do
    {:reply, pub, state}
  end

  def handle_call(:next_public_key, _, state = %{next_keypair: {pub, _}}) do
    {:reply, pub, state}
  end

  def handle_call(
        {:diffie_hellman_first, public_key},
        _,
        state = %{first_keypair: {_, <<curve_id::8, _::8, pv::binary>>}}
      ) do
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

  def handle_call(
        {:diffie_hellman_last, public_key},
        _,
        state = %{last_keypair: {_, <<curve_id::8, _::8, pv::binary>>}}
      ) do
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

  @impl GenServer
  def handle_cast(:persist_next_keypair, state = %{index: index, seed: seed}) do
    next_keypair = Crypto.derive_keypair(seed, index + 2)
    previous_keypair = Crypto.derive_keypair(seed, index + 1)
    last_keypair = Crypto.derive_keypair(seed, index)

    new_state =
      state
      |> Map.update!(:index, &(&1 + 1))
      |> Map.put(:next_keypair, next_keypair)
      |> Map.put(:previous_keypair, previous_keypair)
      |> Map.put(:last_keypair, last_keypair)

    Logger.info("Next public key will be #{Base.encode16(elem(next_keypair, 0))}")
    Logger.info("Previous public key will be #{Base.encode16(elem(previous_keypair, 0))}")
    Logger.info("Publication/Last public key will be #{Base.encode16(elem(last_keypair, 0))}")

    File.write(Utils.mut_dir("crypto/index"), "#{index + 1}")

    {:noreply, new_state}
  end
end
