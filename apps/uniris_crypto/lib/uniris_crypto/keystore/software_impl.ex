defmodule UnirisCrypto.Keystore.SoftwareImpl do
  @moduledoc false

  use GenServer

  alias UnirisCrypto, as: Crypto

  @behaviour UnirisCrypto.Keystore.Impl

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    node_seed = Keyword.get(opts, :seed)
    {:ok, %{node_seed: node_seed, node_key_counter: 0}}
  end

  @impl true
  def handle_call(
        {:sign_with_node_key, data},
        _,
        state = %{node_key_counter: index, node_seed: seed}
      ) do
    {_, pv} = Crypto.derivate_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call({:sign_with_node_key, data, index}, _, state = %{node_seed: seed}) do
    {_, pv} = Crypto.derivate_keypair(seed, index)
    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call({:sign_with_origin_key, data}, _, state = %{origin_seeds: origin_seeds}) do
    {_, pv} =
      origin_seeds
      |> Enum.random()
      |> Crypto.generate_deterministic_keypair()

    {:reply, Crypto.sign(data, pv), state}
  end

  def handle_call({:hash_with_daily_nonce, data}, _, state = %{daily_nonce_keys: {_, pv}}) do
    {:reply, Crypto.hash([pv, data]), state}
  end

  def handle_call({:hash_with_storage_nonce, data}, _, state = %{storage_nonce_keys: {_, pv}}) do
    {:reply, Crypto.hash([pv, data]), state}
  end

  def handle_call(:origin_public_keys, _, state = %{origin_seeds: origin_seeds}) do
    origin_public_keys =
      Enum.map(origin_seeds, fn seed ->
        {pub, _} = Crypto.generate_deterministic_keypair(seed)
        pub
      end)

    {:reply, origin_public_keys, state}
  end

  def handle_call(:node_public_key, _, state = %{node_seed: seed, node_key_counter: index}) do
    {pub, _} = Crypto.derivate_keypair(seed, index)
    {:reply, pub, state}
  end

  def handle_call({:node_public_key, index}, _, state = %{node_seed: seed}) do
    {pub, _} = Crypto.derivate_keypair(seed, index)
    {:reply, pub, state}
  end

  def handle_call(
        {:decrypt_with_node_key, cipher},
        _,
        state = %{node_seed: seed, node_key_counter: index}
      ) do
    try do
      {_, pv} = Crypto.derivate_keypair(seed, index)
      {:reply, Crypto.ec_decrypt!(cipher, pv), state}
    rescue
      _ ->
        {:reply, {:error, :decryption_failed}, state}
    end
  end

  def handle_call(
        {:derivate_beacon_chain_address, subset, date},
        _,
        state = %{storage_nonce_keys: {_, pv}}
      ) do
    {pub, _} =
      Crypto.derivate_keypair(pv, Crypto.hash([subset, date]) |> :binary.decode_unsigned())

    {:reply, Crypto.hash(pub), state}
  end

  @impl true
  def handle_cast(:inc_node_key_counter, state) do
    {:noreply, Map.update!(state, :node_key_counter, &(&1 + 1))}
  end

  def handle_cast({:add_origin_seed, seed}, state) do
    {:noreply, Map.update(state, :origin_seeds, [seed], &(&1 ++ [seed]))}
  end

  def handle_cast({:set_daily_nonce, seed}, state) do
    daily_nonce_keypair = Crypto.generate_deterministic_keypair(seed)
    {:noreply, Map.put(state, :daily_nonce_keys, daily_nonce_keypair)}
  end

  def handle_cast({:set_storage_nonce, seed}, state) do
    storage_nonce_keypair = Crypto.generate_deterministic_keypair(seed)
    {:noreply, Map.put(state, :storage_nonce_keys, storage_nonce_keypair)}
  end

  @impl true
  def sign_with_node_key(data) do
    GenServer.call(__MODULE__, {:sign_with_node_key, data})
  end

  @impl true
  def sign_with_node_key(data, index) do
    GenServer.call(__MODULE__, {:sign_with_node_key, data, index})
  end

  @impl true
  def sign_with_origin_key(data) do
    GenServer.call(__MODULE__, {:sign_with_origin_key, data})
  end

  @impl true
  def origin_public_keys() do
    GenServer.call(__MODULE__, :origin_public_keys)
  end

  @impl true
  def hash_with_daily_nonce(data) do
    GenServer.call(__MODULE__, {:hash_with_daily_nonce, data})
  end

  @impl true
  def hash_with_storage_nonce(data) do
    GenServer.call(__MODULE__, {:hash_with_storage_nonce, data})
  end

  @impl true
  def add_origin_seed(seed) do
    GenServer.cast(
      __MODULE__,
      {:add_origin_seed, seed}
    )
  end

  @impl true
  def set_daily_nonce(seed) do
    GenServer.cast(
      __MODULE__,
      {:set_daily_nonce, seed}
    )
  end

  @impl true
  def set_storage_nonce(seed) do
    GenServer.cast(
      __MODULE__,
      {:set_storage_nonce, seed}
    )
  end

  @impl true
  def node_public_key() do
    GenServer.call(__MODULE__, :node_public_key)
  end

  @impl true
  def node_public_key(index) do
    GenServer.call(__MODULE__, {:node_public_key, index})
  end

  @impl true
  def increment_number_of_generate_node_keys() do
    GenServer.cast(__MODULE__, :inc_node_key_counter)
  end

  @impl true
  def decrypt_with_node_key!(cipher) do
    case GenServer.call(__MODULE__, {:decrypt_with_node_key, cipher}) do
      {:error, :decryption_failed} ->
        raise "Decryption failed"

      result ->
        result
    end
  end

  @impl true
  def derivate_beacon_chain_address(subset, date) do
    GenServer.call(__MODULE__, {:derivate_beacon_chain_address, subset, date})
  end
end
