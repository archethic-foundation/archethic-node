defmodule Uniris.Crypto do
  @moduledoc ~S"""
  Provide cryptographic operations for Uniris network.

  An algorithm identification is produced as a first byte from keys and hashes.
  This identification helps to determine which algorithm/implementation to use in key generation,
  signatures, encryption or hashing.

      Ed25519    Public key
        |           /
        |          /
      <<0, 106, 58, 193, 73, 144, 121, 104, 101, 53, 140, 125, 240, 52, 222, 35, 181,
      13, 81, 241, 114, 227, 205, 51, 167, 139, 100, 176, 111, 68, 234, 206, 72>>

       NIST P-256   Public key
        |          /
        |         /
      <<1, 4, 7, 161, 46, 148, 183, 43, 175, 150, 13, 39, 6, 158, 100, 2, 46, 167,
       101, 222, 82, 108, 56, 71, 28, 192, 188, 104, 154, 182, 87, 11, 218, 58, 107,
      222, 154, 48, 222, 193, 176, 88, 174, 1, 6, 154, 72, 28, 217, 222, 147, 106,
      73, 150, 128, 209, 93, 99, 115, 17, 39, 96, 47, 203, 104, 34>>

  Some functions rely on software implementations such as hashing, encryption or signature verification.
  Other can rely on hardware or software as a configuration choice to generate keys, sign or decrypt data.
  According to the implementation, keys can be stored and regenerated on the fly
  """

  alias __MODULE__.ECDSA
  alias __MODULE__.Ed25519
  alias __MODULE__.ID
  alias __MODULE__.Keystore
  alias __MODULE__.KeystoreLoader

  alias Uniris.TransactionChain.Transaction
  alias Uniris.Utils

  require Logger

  @typedoc """
  List of the supported hash algorithms
  """
  @type supported_hash :: :sha256 | :sha512 | :sha3_256 | :sha3_512 | :blake2b

  @typedoc """
  List of the supported elliptic curves
  """
  @type supported_curve :: :ed25519 | ECDSA.curve()

  @typedoc """
  Binary representing a hash prepend by a single byte to identify the algorithm of the generated hash
  """
  @type versioned_hash :: <<_::8, _::_*8>>

  @typedoc """
  Binary representing a key prepend by a single byte to identify the elliptic curve for a key
  """
  @type key :: <<_::8, _::_*8>>

  @typedoc """
  Binary representing a AES key on 32 bytes
  """
  @type aes_key :: <<_::256>>

  @typedoc """
  Binary representing an encrypted data using AES authenticated encryption.
  The binary is split following this rule:
  - 12 bytes for the IV (Initialization Vector)
  - 16 bytes for the Authentication tag
  - The rest for the ciphertext
  """
  @type aes_cipher :: <<_::384, _::_*8>>

  @doc """
  Derive a new keypair from a seed (retrieved from the local keystore
  and an index representing the number of previous generate keypair.

  The seed generates a master key and an entropy used in the child keys generation.

                                                               / (256 bytes) Next private key
                          (256 bytes) Master key  --> HMAC-512
                        /                              Key: Master entropy,
      seed --> HMAC-512                                Data: Master key + index)
                        \
                         (256 bytes) Master entropy



  ## Examples

      iex> {pub, _} = Crypto.derive_keypair("myseed", 1)
      iex> {pub10, _} = Crypto.derive_keypair("myseed", 10)
      iex> {pub_bis, _} = Crypto.derive_keypair("myseed", 1)
      iex> pub != pub10 and pub == pub_bis
      true
  """
  @spec derive_keypair(
          seed :: binary(),
          additional_data :: non_neg_integer() | binary(),
          curve :: __MODULE__.supported_curve()
        ) :: {public_key :: key(), private_key :: key()}
  def derive_keypair(
        seed,
        additional_data,
        curve \\ Application.get_env(:uniris, __MODULE__)[:default_curve]
      )

  def derive_keypair(
        seed,
        index,
        curve
      )
      when is_binary(seed) and is_integer(index) do
    seed
    |> get_extended_seed(<<index::32>>)
    |> generate_deterministic_keypair(curve)
  end

  def derive_keypair(
        seed,
        additional_data,
        curve
      )
      when is_binary(seed) and is_binary(additional_data) do
    seed
    |> get_extended_seed(additional_data)
    |> generate_deterministic_keypair(curve)
  end

  @doc """
  Retrieve the storage nonce
  """
  @spec storage_nonce() :: binary()
  def storage_nonce, do: :persistent_term.get(:storage_nonce)

  @doc """
  Generate the address for the beacon chain for a given transaction subset (two first digit of the address)
  and a date represented as timestamp using the storage nonce

  The date can be either a specific datetime or a specific day
  """
  @spec derive_beacon_chain_address(subset :: binary(), date :: DateTime.t()) :: binary()
  def derive_beacon_chain_address(subset, date = %DateTime{}) when is_binary(subset) do
    {pub, _} =
      derive_keypair(
        :persistent_term.get(:storage_nonce),
        hash([subset, <<DateTime.to_unix(date)::32>>]) |> :binary.decode_unsigned()
      )

    hash(pub)
  end

  @doc """
  Derive a keypair for oracle transactions based on a name and a datetime
  """
  @spec derive_oracle_keypair(DateTime.t()) :: {key(), key()}
  def derive_oracle_keypair(datetime = %DateTime{}) do
    derive_keypair(
      :persistent_term.get(:storage_nonce),
      hash([<<DateTime.to_unix(datetime)::32>>])
    )
  end

  @doc """
  Store the encrypted daily nonce seed in the keystore by decrypting with the given secret key
  """
  @spec decrypt_and_set_daily_nonce_seed(
          encrypted_seed :: binary(),
          encrypted_secret_key :: binary()
        ) :: :ok
  def decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_secret_key)
      when is_binary(encrypted_seed) and is_binary(encrypted_secret_key) do
    Keystore.decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_secret_key)
    Logger.info("Daily nonce stored")
  end

  @doc """
  Store the storage nonce in memory by decrypting it using the last node private key
  """
  @spec decrypt_and_set_storage_nonce(encrypted_nonce :: binary()) :: :ok
  def decrypt_and_set_storage_nonce(encrypted_nonce) when is_binary(encrypted_nonce) do
    storage_nonce = ec_decrypt_with_node_key!(encrypted_nonce)
    storage_nonce_path = storage_nonce_filepath()
    :ok = File.mkdir_p!(Path.dirname(storage_nonce_path))
    :ok = File.write(storage_nonce_path, storage_nonce, [:write])
    :ok = :persistent_term.put(:storage_nonce, storage_nonce)
    Logger.info("Storage nonce stored")
  end

  @doc """
  Store the encrypted network pool seed in the keystore by decrypting with the given secret key
  """
  @spec decrypt_and_set_node_shared_secrets_network_pool_seed(
          encrypted_seed :: binary(),
          encrypted_secret_key :: binary()
        ) :: :ok
  def decrypt_and_set_node_shared_secrets_network_pool_seed(encrypted_seed, encrypted_secret_key)
      when is_binary(encrypted_seed) and is_binary(encrypted_secret_key) do
    Keystore.decrypt_and_set_node_shared_secrets_network_pool_seed(
      encrypted_seed,
      encrypted_secret_key
    )

    Logger.info("Network pool shared secrets transaction seed stored")
  end

  @doc """
  Encrypt the storage nonce from memory using the given public key
  """
  @spec encrypt_storage_nonce(key()) :: binary()
  def encrypt_storage_nonce(public_key) when is_binary(public_key) do
    ec_encrypt(:persistent_term.get(:storage_nonce), public_key)
  end

  @doc """
  Store the encrypted daily nonce seed in the keystore by decrypting with the given secret key
  """
  @spec decrypt_and_set_node_shared_secrets_transaction_seed(
          encrypted_seed :: binary(),
          encrypted_secret_key :: binary()
        ) :: :ok
  def decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_seed, encrypted_secret_key)
      when is_binary(encrypted_seed) and is_binary(encrypted_secret_key) do
    Keystore.decrypt_and_set_node_shared_secrets_transaction_seed(
      encrypted_seed,
      encrypted_secret_key
    )

    Logger.info("Node shared secrets transaction seed stored")
  end

  @doc """
  Encrypt the node shared secrets transaction seed located in the keystore using the given secret key
  """
  @spec encrypt_node_shared_secrets_transaction_seed(aes_key :: binary()) :: binary()
  defdelegate encrypt_node_shared_secrets_transaction_seed(aes_key), to: Keystore

  defp get_extended_seed(seed, additional_data) do
    <<master_key::binary-32, master_entropy::binary-32>> = :crypto.hmac(:sha512, "", seed)

    <<extended_pv::binary-32, _::binary-32>> =
      :crypto.hmac(:sha512, master_entropy, master_key <> additional_data)

    extended_pv
  end

  @doc """
  Return the last node public key
  """
  @spec node_public_key() :: key()
  defdelegate node_public_key, to: Keystore

  @doc """
  Return a node public key by using key derivation from an index

  ## Examples

    iex> pub0 = Crypto.node_public_key(0)
    iex> pub10 = Crypto.node_public_key(10)
    iex> pub0_bis = Crypto.node_public_key(0)
    iex> pub0 != pub10 and pub0 == pub0_bis
    true
  """
  @spec node_public_key(index :: number()) :: key()
  defdelegate node_public_key(index), to: Keystore

  @doc """
  Return the the node shared secrets public key using the node shared secret transaction seed
  """
  @spec node_shared_secrets_public_key(index :: number()) :: key()
  defdelegate node_shared_secrets_public_key(index), to: Keystore

  @doc """
  Return the storage nonce public key
  """
  @spec storage_nonce_public_key() :: binary()
  def storage_nonce_public_key do
    {pub, _} = derive_keypair(:persistent_term.get(:storage_nonce), 0)
    pub
  end

  @doc """
  Decrypt a cipher using the storage nonce public key using an authenticated encryption (ECIES).

  More details at `ec_decrypt/2`
  """
  @spec ec_decrypt_with_storage_nonce(iodata()) :: {:ok, binary()} | {:error, :decryption_failed}
  def ec_decrypt_with_storage_nonce(data) when is_bitstring(data) or is_list(data) do
    {_, pv} = derive_keypair(:persistent_term.get(:storage_nonce), 0)
    ec_decrypt(data, pv)
  end

  @doc """
  Increment the counter for the number of generated node private keys.
  This number is used for the key derivation to detect the latest index.
  """
  @spec increment_number_of_generate_node_keys() :: :ok
  def increment_number_of_generate_node_keys do
    Keystore.increment_number_of_generate_node_keys()
    nb = Keystore.number_of_node_keys()
    Logger.info("Node key index incremented (#{nb})")
  end

  @doc """
  Increment the counter for the number of generated node shared secrets private keys.
  This number is used for the key derivation to detect the latest index.
  """
  @spec increment_number_of_generate_node_shared_secrets_keys() :: :ok
  def increment_number_of_generate_node_shared_secrets_keys do
    Keystore.increment_number_of_generate_node_shared_secrets_keys()
    nb = Keystore.number_of_node_shared_secrets_keys()
    Logger.info("Node shared key index incremented (#{nb})")
  end

  @doc """
  Return the number of node keys after incrementation
  """
  @spec number_of_node_keys() :: non_neg_integer()
  defdelegate number_of_node_keys, to: Keystore

  @doc """
  Return the number of node shared secrets keys after incrementation
  """
  @spec number_of_node_shared_secrets_keys() :: non_neg_integer()
  defdelegate number_of_node_shared_secrets_keys, to: Keystore

  @doc """
  Generate a keypair in a deterministic way using a seed

  ## Examples

      iex> {pub, _} = Crypto.generate_deterministic_keypair("myseed")
      iex> pub
      <<0, 91, 43, 89, 132, 233, 51, 190, 190, 189, 73, 102, 74, 55, 126, 44, 117, 50,
      36, 220, 249, 242, 73, 105, 55, 83, 190, 3, 75, 113, 199, 247, 165>>

      iex> {pub, _} = Crypto.generate_deterministic_keypair("myseed", :secp256r1)
      iex> pub
      <<1, 4, 140, 235, 188, 198, 146, 160, 92, 132, 81, 177, 113, 230, 39, 220, 122,
      112, 231, 18, 90, 66, 156, 47, 54, 192, 141, 44, 45, 223, 115, 28, 30, 48,
      105, 253, 171, 105, 87, 148, 108, 150, 86, 128, 28, 102, 163, 51, 28, 57, 33,
      133, 109, 49, 202, 92, 184, 138, 187, 26, 123, 45, 5, 94, 180, 250>>

  """
  @spec generate_deterministic_keypair(
          seed :: binary(),
          curve :: __MODULE__.supported_curve()
        ) :: {public_key :: key(), private_key :: key()}
  def generate_deterministic_keypair(
        seed,
        curve \\ Application.get_env(:uniris, __MODULE__)[:default_curve]
      )
      when is_binary(seed) do
    do_generate_deterministic_keypair(curve, seed)
  end

  defp do_generate_deterministic_keypair(:ed25519, seed) do
    seed
    |> Ed25519.generate_keypair()
    |> ID.prepend_keypair(:ed25519)
  end

  defp do_generate_deterministic_keypair(curve, seed) do
    curve
    |> ECDSA.generate_keypair(seed)
    |> ID.prepend_keypair(curve)
  end

  @doc """
  Sign data.

  The first byte of the private key identifies the curve and the signature algorithm to use

  ## Examples

      iex> {_pub, pv} = Crypto.generate_deterministic_keypair("myseed")
      iex> Crypto.sign("myfakedata", pv)
      <<27, 255, 138, 135, 216, 145, 51, 246, 201, 113, 139, 48, 249, 222, 114, 191,
      122, 83, 221, 14, 45, 82, 89, 193, 75, 141, 89, 136, 107, 140, 147, 27, 172,
      25, 22, 200, 125, 103, 19, 39, 205, 60, 199, 176, 113, 134, 204, 45, 7, 182,
      89, 7, 214, 145, 114, 135, 229, 177, 11, 221, 12, 24, 15, 12>>
  """
  @spec sign(data :: iodata(), private_key :: binary()) :: signature :: binary()
  def sign(data, _private_key = <<curve_id::8, key::binary>>)
      when is_bitstring(data) or is_list(data) do
    curve_id
    |> ID.to_curve()
    |> do_sign(Utils.wrap_binary(data), key)
  end

  defp do_sign(:ed25519, data, key), do: Ed25519.sign(key, data)
  defp do_sign(curve, data, key), do: ECDSA.sign(curve, key, data)

  @doc """
  Sign the data with the last node private key
  """
  @spec sign_with_node_key(data :: iodata() | bitstring() | [bitstring]) :: binary()
  def sign_with_node_key(data) when is_bitstring(data) or is_list(data) do
    data
    |> Utils.wrap_binary()
    |> Keystore.sign_with_node_key()
  end

  @doc """
  Sign the data with the private key at the given index.
  """
  @spec sign_with_node_key(data :: iodata(), index :: non_neg_integer()) :: binary()
  def sign_with_node_key(data, index)
      when (is_bitstring(data) or is_list(data)) and is_integer(index) and index >= 0 do
    data
    |> Utils.wrap_binary()
    |> Keystore.sign_with_node_key(index)
  end

  @doc """
  Sign the data with the node shared secrets transaction seed
  """
  @spec sign_with_node_shared_secrets_key(data :: iodata()) :: binary()
  def sign_with_node_shared_secrets_key(data) when is_bitstring(data) or is_list(data) do
    data
    |> Utils.wrap_binary()
    |> Keystore.sign_with_node_shared_secrets_key()
  end

  @doc """
  Sign the data with the node shared secrets transaction seed
  """
  @spec sign_with_node_shared_secrets_key(data :: iodata(), index :: non_neg_integer()) ::
          binary()
  def sign_with_node_shared_secrets_key(data, index)
      when (is_bitstring(data) or is_list(data)) and is_integer(index) and index >= 0 do
    data
    |> Utils.wrap_binary()
    |> Keystore.sign_with_node_shared_secrets_key(index)
  end

  @doc """
  Verify a signature.

  The first byte of the public key identifies the curve and the verification algorithm to use.

  ## Examples

      iex> {pub, pv} = Crypto.generate_deterministic_keypair("myseed")
      iex> sig = Crypto.sign("myfakedata", pv)
      iex> Crypto.verify(sig, "myfakedata", pub)
      true

  Returns false when the signature is invalid
      iex> {pub, _} = Crypto.generate_deterministic_keypair("myseed")
      iex> sig = <<1, 48, 69, 2, 33, 0, 185, 231, 7, 86, 207, 253, 8, 230, 199, 94, 251, 33, 42, 172, 95, 93, 7, 209, 175, 69, 216, 121, 239, 24, 17, 21, 41, 129, 255, 49, 153, 116, 2, 32, 85, 1, 212, 69, 182, 98, 174, 213, 79, 154, 69, 84, 149, 126, 169, 44, 98, 64, 21, 211, 20, 235, 165, 97, 61, 8, 239, 194, 196, 177, 46, 199>>
      iex> Crypto.verify(sig, "myfakedata", pub)
      false
  """
  @spec verify(
          signature :: binary(),
          data :: iodata() | bitstring() | [bitstring],
          public_key :: key()
        ) ::
          boolean()
  def verify(
        sig,
        data,
        <<curve_id::8, key::binary>> = _public_key
      )
      when is_bitstring(data) or is_list(data) do
    curve_id
    |> ID.to_curve()
    |> do_verify(key, Utils.wrap_binary(data), sig)
  end

  defp do_verify(:ed25519, key, data, sig), do: Ed25519.verify(key, data, sig)
  defp do_verify(curve, key, data, sig), do: ECDSA.verify(curve, key, data, sig)

  @doc """
  Encrypts data using public key authenticated encryption (ECIES).

  Ephemeral and random ECDH key pair is generated which is used to generate shared
  secret with the given public key(transformed to ECDH public key).

  Based on this secret, KDF derive keys are used to create an authenticated symmetric encryption.

  ## Examples

      ```
      pub = {pub, _} = Crypto.generate_deterministic_keypair("myseed")
      Crypto.ec_encrypt("myfakedata", pub)
      <<0, 0, 0, 58, 211, 32, 254, 247, 110, 135, 236, 224, 119, 89, 142, 210, 120,
      111, 59, 77, 4, 17, 199, 94, 66, 116, 251, 92, 77, 231, 78, 11, 123, 112, 201,
      116, 41, 23, 6, 157, 49, 93, 11, 235, 175, 242, 225, 250, 241, 196, 207, 83,
      172, 79, 3, 206, 21, 227, 227, 156, 55, 112>>
      ```
  """
  @spec ec_encrypt(message :: binary(), public_key :: key()) :: binary()
  def ec_encrypt(message, <<curve_id::8, key::binary>> = _public_key) when is_binary(message) do
    curve_id
    |> ID.to_curve()
    |> do_ec_encrypt(message, key)
  end

  defp do_ec_encrypt(:ed25519, message, public_key), do: Ed25519.encrypt(public_key, message)
  defp do_ec_encrypt(curve, message, public_key), do: ECDSA.encrypt(curve, public_key, message)

  @doc """
  Decrypt a cipher using public key authenticated encryption (ECIES).

  A cipher contains a generated ephemeral random public key coupled with an authentication tag.

  Private key is transformed to ECDH to compute a shared secret with this random public key.

  Based on this secret, KDF derive keys are used to create an authenticated symmetric decryption.

  Before the decryption, the authentication will be checked to ensure the given private key
  has the right to decrypt this data.

  ## Examples

      iex> cipher = <<211, 32, 254, 247, 110, 135, 236, 224, 119, 89, 142, 210, 120,
      ...> 111, 59, 77, 4, 17, 199, 94, 66, 116, 251, 92, 77, 231, 78, 11, 123, 112, 201,
      ...> 116, 41, 23, 6, 157, 49, 93, 11, 235, 175, 242, 225, 250, 241, 196, 207, 83,
      ...> 172, 79, 3, 206, 21, 227, 227, 156, 55, 112>>
      iex> {_pub, pv} = Crypto.generate_deterministic_keypair("myseed")
      iex> Uniris.Crypto.ec_decrypt!(cipher, pv)
      "myfakedata"

  Invalid message to decrypt or key return an error:

      ```
      Crypto.generate_deterministic_keypair("myseed")
      Crypto.ec_decrypt!(<<0, 0, 0>>, :node)
      ** (RuntimeError) Decryption failed
      ```
  """
  @spec ec_decrypt!(cipher :: binary(), private_key :: key()) :: binary()
  def ec_decrypt!(cipher, _private_key = <<curve_id::8, key::binary>>) when is_binary(cipher) do
    curve_id
    |> ID.to_curve()
    |> do_ec_decrypt!(cipher, key)
  end

  @doc """

  ## Examples

      iex> cipher = <<211, 32, 254, 247, 110, 135, 236, 224, 119, 89, 142, 210, 120,
      ...> 111, 59, 77, 4, 17, 199, 94, 66, 116, 251, 92, 77, 231, 78, 11, 123, 112, 201,
      ...> 116, 41, 23, 6, 157, 49, 93, 11, 235, 175, 242, 225, 250, 241, 196, 207, 83,
      ...> 172, 79, 3, 206, 21, 227, 227, 156, 55, 112>>
      iex> {_pub, pv} = Crypto.generate_deterministic_keypair("myseed")
      iex> {:ok, "myfakedata"} = Crypto.ec_decrypt(cipher, pv)

  Invalid message to decrypt return an error:

      iex> {_, pv} = Crypto.generate_deterministic_keypair("myseed")
      iex> Crypto.ec_decrypt(<<0, 0, 0>>, pv)
      {:error, :decryption_failed}
  """
  @spec ec_decrypt(binary(), binary()) :: {:ok, binary()} | {:error, :decryption_failed}
  def ec_decrypt(cipher, _private_key = <<curve_id::8, key::binary>>) when is_binary(cipher) do
    data =
      curve_id
      |> ID.to_curve()
      |> do_ec_decrypt!(cipher, key)

    {:ok, data}
  rescue
    _ ->
      {:error, :decryption_failed}
  end

  @doc """
  Decrypt the cipher using last node private key
  """
  @spec ec_decrypt_with_node_key!(cipher :: binary()) :: term()
  defdelegate ec_decrypt_with_node_key!(cipher), to: Keystore, as: :decrypt_with_node_key!

  @doc """
  Decrypt the cipher using a given node private key
  """
  @spec ec_decrypt_with_node_key!(cipher :: binary(), index :: non_neg_integer()) :: binary()
  defdelegate ec_decrypt_with_node_key!(cipher, index), to: Keystore, as: :decrypt_with_node_key!

  defp do_ec_decrypt!(:ed25519, cipher, key), do: Ed25519.decrypt(key, cipher)
  defp do_ec_decrypt!(curve, cipher, key), do: ECDSA.decrypt(curve, key, cipher)

  @doc """
  Encrypt a data using AES authenticated encryption.
  """
  @spec aes_encrypt(data :: iodata(), key :: iodata()) :: aes_cipher
  def aes_encrypt(data, _key = <<key::binary-32>>) when is_binary(data) do
    iv = :crypto.strong_rand_bytes(12)
    {cipher, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, data, "", true)
    iv <> tag <> cipher
  end

  @doc """
  Decrypt a ciphertext using the AES authenticated decryption.

  ## Examples

      iex> key = <<234, 210, 202, 129, 91, 76, 68, 14, 17, 212, 197, 49, 66, 168, 52, 111, 176,
      ...> 182, 227, 156, 5, 32, 24, 105, 41, 152, 67, 191, 187, 209, 101, 36>>
      iex> ciphertext = Crypto.aes_encrypt("sensitive data", key)
      iex> Crypto.aes_decrypt!(ciphertext, key)
      "sensitive data"

  Return an error when the key is invalid

      ```
      ciphertext = Crypto.aes_encrypt("sensitive data", :crypto.strong_rand_bytes(32))
      Crypto.aes_decrypt!(ciphertext, :crypto.strong_rand_bytes(32))
      ** (RuntimeError) Decryption failed
      ```

  """
  @spec aes_decrypt!(cipher :: aes_cipher, key :: binary) :: binary()
  def aes_decrypt!(<<iv::binary-12, tag::binary-16, cipher::binary>>, <<key::binary-32>>) do
    case :crypto.crypto_one_time_aead(
           :aes_256_gcm,
           key,
           iv,
           cipher,
           "",
           tag,
           false
         ) do
      :error ->
        raise "Decryption failed"

      data ->
        data
    end
  end

  @doc """
  Decrypt a ciphertext using the AES authenticated decryption.

  ## Examples

      iex> key = <<234, 210, 202, 129, 91, 76, 68, 14, 17, 212, 197, 49, 66, 168, 52, 111, 176,
      ...> 182, 227, 156, 5, 32, 24, 105, 41, 152, 67, 191, 187, 209, 101, 36>>
      iex> ciphertext = Crypto.aes_encrypt("sensitive data", key)
      iex> Crypto.aes_decrypt(ciphertext, key)
      {:ok, "sensitive data"}

  Return an error when the key is invalid

      iex> ciphertext = Crypto.aes_encrypt("sensitive data", :crypto.strong_rand_bytes(32))
      iex> Crypto.aes_decrypt(ciphertext, :crypto.strong_rand_bytes(32))
      {:error, :decryption_failed}

  """
  def aes_decrypt(data = <<_::binary-12, _::binary-16, _::binary>>, <<key::binary-32>>) do
    {:ok, aes_decrypt!(data, key)}
  rescue
    _ ->
      {:error, :decryption_failed}
  end

  @doc """
  Hash a data.

  A first-byte prepends each hash to indicate the algorithm used.

  ## Examples

      iex> Crypto.hash("myfakedata", :sha256)
      <<0, 78, 137, 232, 16, 150, 235, 9, 199, 74, 41, 189, 246, 110, 65, 252, 17,
      139, 109, 23, 172, 84, 114, 35, 202, 102, 41, 167, 23, 36, 230, 159, 35>>

      iex> Crypto.hash("myfakedata", :blake2b)
      <<4, 244, 16, 24, 144, 16, 67, 113, 164, 214, 115, 237, 113, 126, 130, 76, 128,
      99, 78, 223, 60, 179, 158, 62, 239, 245, 85, 4, 156, 10, 2, 94, 95, 19, 166,
      170, 147, 140, 117, 1, 169, 132, 113, 202, 217, 193, 56, 112, 193, 62, 134,
      145, 233, 114, 41, 228, 164, 180, 225, 147, 2, 33, 192, 42, 184>>

      iex> Crypto.hash("myfakedata", :sha3_256)
      <<2, 157, 219, 54, 234, 186, 251, 4, 122, 216, 105, 185, 228, 211, 94, 44, 94,
      104, 147, 182, 189, 45, 28, 219, 218, 236, 19, 66, 87, 121, 240, 249, 218>>
  """
  @spec hash(data :: iodata(), algo :: supported_hash()) :: versioned_hash()
  def hash(data, algo \\ Application.get_env(:uniris, __MODULE__)[:default_hash])

  def hash(data, algo) when is_bitstring(data) or is_list(data) do
    data
    |> Utils.wrap_binary()
    |> do_hash(algo)
    |> ID.prepend_hash(algo)
  end

  defp do_hash(data, :sha256), do: :crypto.hash(:sha256, data)
  defp do_hash(data, :sha512), do: :crypto.hash(:sha512, data)
  defp do_hash(data, :sha3_256), do: :crypto.hash(:sha3_256, data)
  defp do_hash(data, :sha3_512), do: :crypto.hash(:sha3_512, data)
  defp do_hash(data, :blake2b), do: :crypto.hash(:blake2b, data)

  @doc """
  Hash data with the daily nonce stored in the keystore
  """
  @spec hash_with_daily_nonce(data :: iodata()) :: binary()
  defdelegate hash_with_daily_nonce(data), to: Keystore

  @doc """
  Hash the data using the storage nonce stored in memory
  """
  @spec hash_with_storage_nonce(data :: iodata()) :: binary()
  def hash_with_storage_nonce(data) when is_binary(data) or is_list(data) do
    hash([:persistent_term.get(:storage_nonce), data])
  end

  @doc """
  Return the size of key using the curve id

  ## Examples

      iex> Crypto.key_size(ID.from_curve(:ed25519))
      32

      iex> Crypto.key_size(ID.from_curve(:secp256r1))
      65

      iex> Crypto.key_size(ID.from_curve(:secp256k1))
      65
  """
  @spec key_size(curve_id :: 0 | 1 | 2) :: 32 | 65
  def key_size(0), do: 32
  def key_size(1), do: 65
  def key_size(2), do: 65

  @doc """
  Determine if a public key is valid
  """
  @spec valid_public_key?(binary()) :: boolean()
  def valid_public_key?(<<0::8, _::binary-size(32)>>), do: true
  def valid_public_key?(<<1::8, _::binary-size(65)>>), do: true
  def valid_public_key?(<<2::8, _::binary-size(65)>>), do: true
  def valid_public_key?(_), do: false

  @doc """
  Return the size of hash using the algorithm id

  ## Examples

      iex> Crypto.hash_size(ID.from_hash(:sha256))
      32

      iex> Crypto.hash_size(ID.from_hash(:sha512))
      64

      iex> Crypto.hash_size(ID.from_hash(:sha3_256))
      32

      iex> Crypto.hash_size(ID.from_hash(:sha3_512))
      64

      iex> Crypto.hash_size(ID.from_hash(:blake2b))
      64
  """
  @spec hash_size(hash_algo_id :: 0 | 1 | 2 | 3 | 4) :: 32 | 64
  def hash_size(0), do: 32
  def hash_size(1), do: 64
  def hash_size(2), do: 32
  def hash_size(3), do: 64
  def hash_size(4), do: 64

  @doc """
  Determine if a hash is valid
  """
  @spec valid_hash?(binary()) :: boolean()
  def valid_hash?(<<0::8, _::binary-size(32)>>), do: true
  def valid_hash?(<<1::8, _::binary-size(64)>>), do: true
  def valid_hash?(<<2::8, _::binary-size(32)>>), do: true
  def valid_hash?(<<3::8, _::binary-size(64)>>), do: true
  def valid_hash?(<<4::8, _::binary-size(64)>>), do: true
  def valid_hash?(_), do: false

  @doc """
  Load the transaction for the Keystore indexing
  """
  @spec load_transaction(Transaction.t()) :: :ok
  defdelegate load_transaction(tx), to: KeystoreLoader

  @doc """
  Return the storage nonce filepath
  """
  @spec storage_nonce_filepath() :: binary()
  def storage_nonce_filepath do
    rel_filepath = Application.get_env(:uniris, __MODULE__) |> Keyword.fetch!(:storage_nonce_file)
    Utils.mut_dir(rel_filepath)
  end
end
