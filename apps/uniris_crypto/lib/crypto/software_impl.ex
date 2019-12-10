defmodule UnirisCrypto.SoftwareImpl do
  @moduledoc false

  alias UnirisCrypto.SoftwareImpl.ECDSA
  alias UnirisCrypto.SoftwareImpl.Ed25519
  alias UnirisCrypto.SoftwareImpl.Keystore
  alias UnirisCrypto.ID

  @behaviour UnirisCrypto.Impl

  @impl true
  @spec derivate_keypair(
          index :: non_neg_integer(),
          options :: UnirisCrypto.key_generation_options()
        ) ::
          {:ok, UnirisCrypto.key()}
  def derivate_keypair(index, options)
      when is_integer(index) and index >= 0 and is_list(options) do
    extended_seed = get_extended_seed(Keystore.get_seed(), index)
    curve = Keyword.get(options, :curve)

    with {:ok, curve_id} <- ID.get_id_from_curve(curve) do
      {pub, pv} =
        case curve do
          :ed25519 ->
            with {:ok, pub, pv} <- Ed25519.generate_keypair(extended_seed) do
              {pub, pv}
            end

          curve ->
            ECDSA.generate_keypair(extended_seed, curve)
        end

      case Keyword.get(options, :storage_destination) do
        nil ->
          {:ok, <<curve_id::8>> <> pub}

        destination when destination in [:node, :origin, :shared] ->
          Keystore.set_keypair(destination, <<curve_id::8>> <> pub, <<curve_id::8>> <> pv)
          {:ok, <<curve_id::8>> <> pub}
      end
    end
  end

  def get_extended_seed(seed, index) do
    <<master_key::binary-32, master_entropy::binary-32>> = :crypto.hmac(:sha512, "", seed)

    <<extended_pv::binary-32, _::binary-32>> =
      :crypto.hmac(:sha512, master_entropy, master_key <> <<index>>)

    extended_pv
  end

  @impl true
  @spec generate_random_keypair(options :: UnirisCrypto.key_generation_options()) ::
          {:ok, binary()}
  def generate_random_keypair(options) do
    curve = Keyword.get(options, :curve)

    with {:ok, curve_id} <- ID.get_id_from_curve(curve) do
      {pub, pv} =
        case curve do
          :ed25519 ->
            with {:ok, pub, pv} <- Ed25519.generate_keypair() do
              {pub, pv}
            end

          curve ->
            ECDSA.generate_keypair(curve)
        end

      case Keyword.get(options, :storage_destination) do
        nil ->
          {:ok, <<curve_id::8>> <> pub}

        destination when destination in [:node, :origin, :shared] ->
          Keystore.set_keypair(destination, <<curve_id::8>> <> pub, <<curve_id::8>> <> pv)
          {:ok, <<curve_id::8>> <> pub}
      end
    end
  end

  @spec generate_deterministic_keypair(
          seed :: binary(),
          options :: UnirisCrypto.key_generation_options()
        ) :: {:ok, binary()}
  @impl true
  def generate_deterministic_keypair(seed, options) when is_binary(seed) and is_list(options) do
    curve = Keyword.get(options, :curve)

    with {:ok, curve_id} <- ID.get_id_from_curve(curve) do
      {pub, pv} =
        case curve do
          :ed25519 ->
            with {:ok, pub, pv} <- Ed25519.generate_keypair(seed) do
              {pub, pv}
            end

          curve ->
            ECDSA.generate_keypair(seed, curve)
        end

      case Keyword.get(options, :storage_destination) do
        nil ->
          {:ok, <<curve_id::8>> <> pub}

        destination when destination in [:node, :origin, :shared] ->
          Keystore.set_keypair(destination, <<curve_id::8>> <> pub, <<curve_id::8>> <> pv)
          {:ok, <<curve_id::8>> <> pub}
      end
    end
  end

  @spec sign(data :: binary(), key_access :: UnirisCrypto.key_access()) :: {:ok, binary()}
  @impl true
  def sign(data, key_access)
      when is_binary(data) and is_list(key_access) do
    with source when source in [:node, :origin, :shared] <- Keyword.get(key_access, :source),
         label when label in [:first, :last, :previous] <- Keyword.get(key_access, :label),
         {:ok, <<curve_id::8, key::binary>>} <- Keystore.get_private_key(source, label) do
      with {:ok, curve} <- ID.get_curve_from_id(curve_id) do
        case curve do
          :ed25519 ->
            Ed25519.sign(key, data)

          curve ->
            ECDSA.sign(key, curve, data)
        end
      end
    end
  end

  @impl true
  @spec verify(curve :: atom(), key :: binary, data :: term, sig :: binary()) ::
          :ok | {:error, :invalid_key} | {:error, :invalid_signature}
  def verify(:ed25519, key, data, sig), do: Ed25519.verify(key, data, sig)
  def verify(curve, key, data, sig), do: ECDSA.verify(key, curve, data, sig)

  @impl true
  @spec ec_encrypt(curve :: atom(), public_key :: binary(), message :: binary()) ::
          {:ok, binary()}
  def ec_encrypt(:ed25519, public_key, message),
    do: Ed25519.encrypt(public_key, message)

  def ec_encrypt(curve, public_key, message), do: ECDSA.encrypt(public_key, curve, message)

  @impl true
  @spec ec_decrypt(message :: binary(), key_access :: UnirisCrypto.key_access()) ::
          {:ok, term()} | {:error, :decryption_failed}
  def ec_decrypt(message, key_access)
      when is_binary(message) and is_list(key_access) do
    with source when source in [:node, :origin, :shared] <- Keyword.get(key_access, :source),
         label when label in [:first, :last, :previous] <- Keyword.get(key_access, :label),
         {:ok, <<curve_id::8, key::binary>>} <- Keystore.get_private_key(source, label) do
      with {:ok, curve} <- ID.get_curve_from_id(curve_id) do
        case curve do
          :ed25519 ->
            Ed25519.decrypt(key, message)

          curve ->
            ECDSA.decrypt(key, curve, message)
        end
      end
    end
  end

  @impl true
  @spec aes_encrypt(data :: binary(), key :: UnirisCrypto.aes_key()) :: UnirisCrypto.aes_cipher()
  def aes_encrypt(data, key) when is_binary(data) and is_binary(key) and byte_size(key) == 32 do
    iv = :crypto.strong_rand_bytes(32)
    {cipher, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, data, "", true)
    iv <> tag <> cipher
  end

  @impl true
  @spec aes_decrypt(message :: UnirisCrypto.aes_cipher(), key :: UnirisCrypto.aes_key()) ::
          {:ok, binary()} | {:error, :decryption_failed}
  def aes_decrypt(<<iv::32*8, tag::8*16, cipher::binary>>, key)
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
        {:error, :decryption_failed}

      data ->
        {:ok, data}
    end
  end

  @impl true
  @spec get_public_key(key_access :: UnirisCrypto.key_access()) ::
          {:ok, binary()} | {:error, :missing_key}
  def get_public_key(key_access) when is_list(key_access) do
    with source when source in [:node, :origin, :shared] <- Keyword.get(key_access, :source),
         label when label in [:first, :last, :previous] <- Keyword.get(key_access, :label) do
      Keystore.get_public_key(source, label)
    end
  end
end
