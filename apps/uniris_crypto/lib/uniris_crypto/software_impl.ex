defmodule UnirisCrypto.SoftwareImpl do
  @moduledoc false

  use GenServer

  @behaviour UnirisCrypto.Impl

  alias UnirisCrypto.ID
  alias UnirisCrypto.SoftwareImpl.Ed25519
  alias UnirisCrypto.SoftwareImpl.ECDSA

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    seed = Keyword.get(opts, :seed)
    curve = Application.get_env(:uniris_crypto, :default_curve)
    curve_id = ID.id_from_curve(curve)

    {first_pub, first_pv} =
      do_derivate_keypair(seed, 0, curve)
      |> ID.identify_keypair(curve_id)

    state = %{
      node: %{
        index: 0,
        seed: seed,
        first: %{public_key: first_pub, private_key: first_pv},
        last: %{public_key: first_pub, private_key: first_pv}
      }
    }

    {:ok, state}
  end

  def handle_cast({:generate_shared_keys, seed, index, curve}, state = %{}) do
    curve_id = ID.id_from_curve(curve)

    {first_pub, first_pv} = do_derivate_keypair(seed, 0, curve) |> ID.identify_keypair(curve_id)
    {last_pub, last_pv} = do_derivate_keypair(seed, index, curve) |> ID.identify_keypair(curve_id)

    new_state =
      Map.put(state, :shared, %{
        first: %{public_key: first_pub, private_key: first_pv},
        last: %{public_key: last_pub, private_key: last_pv}
      })

    {:noreply, new_state}
  end

  def handle_cast({:load_origin_keys, keypairs}, state = %{}) do
    new_state = Map.put(state, :origin_keypairs, keypairs)
    {:noreply, new_state}
  end

  def handle_call(
        {:derivate_keypair, index, options},
        _from,
        state = %{node: %{seed: seed, last: last_keypair}}
      ) do
    curve = Keyword.get(options, :curve)
    curve_id = ID.id_from_curve(curve)

    {public_key, private_key} =
      do_derivate_keypair(seed, index, curve)
      |> ID.identify_keypair(curve_id)

    case Keyword.get(options, :persistence) do
      nil ->
        {:reply, public_key, state}

      true ->
        new_state = set_node_keypair(last_keypair, {public_key, private_key}, state)
        {:reply, public_key, new_state}
    end
  end

  def handle_call(
        {:generate_random_keypair, options},
        _from,
        state = %{node: %{last: last_keypair}}
      ) do
    curve = Keyword.get(options, :curve)
    curve_id = ID.id_from_curve(curve)

    {public_key, private_key} =
      generate_keypair(curve)
      |> ID.identify_keypair(curve_id)

    case Keyword.get(options, :persistence) do
      nil ->
        {:reply, public_key, state}

      true ->
        new_state = set_node_keypair(last_keypair, {public_key, private_key}, state)
        {:reply, public_key, new_state}
    end
  end

  def handle_call(
        {:generate_deterministic_keypair, seed, options},
        _from,
        state = %{node: %{last: last_keypair}}
      ) do
    curve = Keyword.get(options, :curve)

    curve_id = ID.id_from_curve(curve)

    {public_key, private_key} =
      generate_keypair(curve, seed)
      |> ID.identify_keypair(curve_id)

    case Keyword.get(options, :persistence) do
      nil ->
        {:reply, public_key, state}

      true ->
        new_state = set_node_keypair(last_keypair, {public_key, private_key}, state)
        {:reply, public_key, new_state}
    end
  end

  def handle_call(
        {:sign, data, [with: :node, as: :first]},
        _from,
        state = %{node: %{first: %{private_key: <<curve_id::8, key::binary>>}}}
      ) do
    {:reply, ID.curve_from_id(curve_id) |> sign(key, data), state}
  end

  def handle_call(
        {:sign, data, [with: :node, as: :last]},
        _from,
        state = %{node: %{last: %{private_key: <<curve_id::8, key::binary>>}}}
      ) do
    {:reply, ID.curve_from_id(curve_id) |> sign(key, data), state}
  end

  def handle_call(
        {:sign, data, [with: :node, as: :previous]},
        _from,
        state = %{node: %{previous: %{private_key: <<curve_id::8, key::binary>>}}}
      ) do
    {:reply, ID.curve_from_id(curve_id) |> sign(key, data), state}
  end

  def handle_call(
        {:sign, data, [with: :shared, as: :first]},
        _from,
        state = %{shared: %{first: %{private_key: <<curve_id::8, key::binary>>}}}
      ) do
    {:reply, ID.curve_from_id(curve_id) |> sign(key, data), state}
  end

  def handle_call(
        {:sign, data, [with: :shared, as: :last]},
        _from,
        state = %{shared: %{last: %{private_key: <<curve_id::8, key::binary>>}}}
      ) do
    {:reply, ID.curve_from_id(curve_id) |> sign(key, data), state}
  end

  def handle_call(
        {:sign, data, [with: :origin, as: :random]},
        _from,
        state = %{origin_keypairs: origin_keypairs}
      ) do
    {_, <<curve_id::8, key::binary>>} = Enum.random(origin_keypairs)
    {:reply, ID.curve_from_id(curve_id) |> sign(key, data), state}
  end

  def handle_call(
        {:decrypt, message, [with: :node, as: :first]},
        _from,
        state = %{node: %{first: %{private_key: <<curve_id::8, key::binary>>}}}
      ) do
    {:reply, ID.curve_from_id(curve_id) |> decrypt(key, message), state}
  end

  def handle_call(
        {:decrypt, message, [with: :node, as: :last]},
        _from,
        state = %{node: %{last: %{private_key: <<curve_id::8, key::binary>>}}}
      ) do
    {:reply, ID.curve_from_id(curve_id) |> decrypt(key, message), state}
  end

  def handle_call(
        {:decrypt, message, [with: :shared, as: :first]},
        _from,
        state = %{shared: %{first: %{private_key: <<curve_id::8, key::binary>>}}}
      ) do
    {:reply, ID.curve_from_id(curve_id) |> decrypt(key, message), state}
  end

  def handle_call(
        {:decrypt, message, [with: :shared, as: :last]},
        _from,
        state = %{shared: %{last: %{private_key: <<curve_id::8, key::binary>>}}}
      ) do
    {:reply, ID.curve_from_id(curve_id) |> decrypt(key, message), state}
  end

  def handle_call(:last_node_public_key, _from, state = %{node: %{last: %{public_key: key}}}) do
    {:reply, key, state}
  end

  def handle_call(:first_node_public_key, _from, state = %{node: %{first: %{public_key: key}}}) do
    {:reply, key, state}
  end

  def handle_call(
        :previous_node_public_key,
        _from,
        state = %{node: %{previous: %{public_key: key}}}
      ) do
    {:reply, key, state}
  end

  def handle_call(
        :first_shared_public_key,
        _from,
        state = %{shared: %{first: %{public_key: key}}}
      ) do
    {:reply, key, state}
  end

  def handle_call(:last_shared_public_key, _from, state = %{shared: %{last: %{public_key: key}}}) do
    {:reply, key, state}
  end

  defp do_derivate_keypair(
         seed,
         index,
         curve
       ) do
    extended_seed = get_extended_seed(seed, index)
    generate_keypair(curve, extended_seed)
  end

  defp get_extended_seed(seed, index) do
    <<master_key::binary-32, master_entropy::binary-32>> = :crypto.hmac(:sha512, "", seed)

    <<extended_pv::binary-32, _::binary-32>> =
      :crypto.hmac(:sha512, master_entropy, master_key <> <<index>>)

    extended_pv
  end

  defp generate_keypair(:ed25519), do: Ed25519.generate_keypair()
  defp generate_keypair(curve), do: ECDSA.generate_keypair(curve)

  defp generate_keypair(:ed25519, seed), do: Ed25519.generate_keypair(seed)
  defp generate_keypair(:secp256r1, seed), do: ECDSA.generate_keypair(seed, :secp256r1)
  defp generate_keypair(:secp256k1, seed), do: ECDSA.generate_keypair(seed, :secp256k1)

  defp sign(:ed25519, key, data), do: Ed25519.sign(key, data)
  defp sign(:secp256k1, key, data), do: ECDSA.sign(key, :secp256k1, data)
  defp sign(:secp256r1, key, data), do: ECDSA.sign(key, :secp256r1, data)

  defp decrypt(:ed25519, key, message), do: Ed25519.decrypt(key, message)
  defp decrypt(:secp256k1, key, message), do: ECDSA.decrypt(key, :secp256k1, message)
  defp decrypt(:secp256r1, key, message), do: ECDSA.decrypt(key, :secp256r1, message)

  defp set_node_keypair(last_keypair, {public_key, private_key}, state) do
    state
    |> put_in([:node, :previous], last_keypair)
    |> put_in([:node, :last], %{public_key: public_key, private_key: private_key})
    |> update_in([:node, :index], &(&1 + 1))
  end

  @spec derivate_keypair(
          index :: non_neg_integer(),
          options :: UnirisCrypto.key_generation_options()
        ) :: UnirisCrypto.key()
  def derivate_keypair(index, options) do
    GenServer.call(__MODULE__, {:derivate_keypair, index, options})
  end

  @spec generate_random_keypair(options :: UnirisCrypto.key_generation_options()) ::
          UnirisCrypto.key()
  def generate_random_keypair(options) do
    GenServer.call(__MODULE__, {:generate_random_keypair, options})
  end

  @spec generate_deterministic_keypair(
          seed :: binary(),
          options :: UnirisCrypto.key_generation_options()
        ) :: UnirisCrypto.key()
  def generate_deterministic_keypair(seed, options) do
    GenServer.call(__MODULE__, {:generate_deterministic_keypair, seed, options})
  end

  @spec sign(data :: binary(), key_access :: UnirisCrypto.key_access()) :: binary()
  def sign(data, key_access) do
    GenServer.call(__MODULE__, {:sign, data, key_access})
  end

  @spec verify(
          curve :: UnirisCrypto.supported_curve(),
          key :: binary,
          data :: term,
          sig :: binary()
        ) :: boolean()
  def verify(:ed25519, key, data, sig), do: Ed25519.verify(key, data, sig)
  def verify(curve, key, data, sig), do: ECDSA.verify(key, curve, data, sig)

  @spec ec_encrypt(
          curve :: UnirisCrypto.supported_curve(),
          public_key :: binary(),
          message :: binary()
        ) ::
          {:ok, binary()}
  def ec_encrypt(:ed25519, public_key, message),
    do: Ed25519.encrypt(public_key, message)

  def ec_encrypt(curve, public_key, message), do: ECDSA.encrypt(public_key, curve, message)

  @spec ec_decrypt!(message :: binary(), key_access :: UnirisCrypto.key_access()) :: term()
  def ec_decrypt!(message, key_access) do
    GenServer.call(__MODULE__, {:decrypt, message, key_access})
  end

  @spec aes_encrypt(data :: binary(), key :: UnirisCrypto.aes_key()) :: UnirisCrypto.aes_cipher()
  def aes_encrypt(data, key) when is_binary(data) and is_binary(key) and byte_size(key) == 32 do
    iv = :crypto.strong_rand_bytes(32)
    {cipher, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, data, "", true)
    iv <> tag <> cipher
  end

  @spec aes_decrypt!(message :: UnirisCrypto.aes_cipher(), key :: UnirisCrypto.aes_key()) ::
          {:ok, binary()} | {:error, :decryption_failed}
  def aes_decrypt!(<<iv::32*8, tag::8*16, cipher::binary>>, key)
      when is_binary(key) and byte_size(key) == 32 do
    case :crypto.crypto_one_time_aead(
           :aes_256_gcm,
           key,
           :binary.encode_unsigned(iv),
           cipher,
           "",
           :binary.encode_unsigned(tag),
           false
         ) do
      :error ->
        raise "Decryption failed"

      data ->
        data
    end
  end

  @spec first_node_public_key() :: UnirisCrypto.key()
  def first_node_public_key() do
    GenServer.call(__MODULE__, :first_node_public_key)
  end

  @spec last_node_public_key() :: UnirisCrypto.key()
  def last_node_public_key() do
    GenServer.call(__MODULE__, :last_node_public_key)
  end

  @spec previous_node_public_key() :: UnirisCrypto.key()
  def previous_node_public_key() do
    GenServer.call(__MODULE__, :previous_node_public_key)
  end

  @spec first_shared_public_key() :: UnirisCrypto.key()
  def first_shared_public_key() do
    GenServer.call(__MODULE__, :first_shared_public_key)
  end

  @spec last_shared_public_key() :: UnirisCrypto.key()
  def last_shared_public_key() do
    GenServer.call(__MODULE__, :last_shared_public_key)
  end

  @spec generate_shared_keys(binary(), pos_integer(), UnirisCrypto.supported_curve()) :: :ok
  def generate_shared_keys(seed, last_index, curve) do
    GenServer.cast(__MODULE__, {:generate_shared_keys, seed, last_index, curve})
  end

  @spec load_origin_keys(list({binary(), binary()})) :: :ok
  def load_origin_keys(keypairs) do
    GenServer.cast(__MODULE__, {:load_origin_keys, keypairs})
  end
end
