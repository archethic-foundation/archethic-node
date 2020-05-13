defmodule UnirisCore.Crypto do
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
  Other can rely on hardware or software as an configuration choice to generate keys, sign or decrypt data.

  A local keystore is implemented through software or hardware according to the configuration choice.
  According to the implementation, keys can be stored and regenerated on the fly
  """

  alias __MODULE__.ID
  alias __MODULE__.ECDSA
  alias __MODULE__.Ed25519
  alias __MODULE__.Keystore

  @typedoc """
  List of the supported hash algorithms
  """
  @type supported_hash :: :sha256 | :sha512 | :sha3_256 | :sha3_512 | :blake2b

  @typedoc """
  List of the supported elliptic curves
  """
  @type supported_curve :: :ed25519 | :secp256r1 | :secp256k1

  @typedoc """
  Binary representing a hash prepend by a single byte to identificate the algorithm of the generated hash
  """
  @type hash :: <<_::8, _::_*8>>

  @typedoc """
  Binary representing a key prepend by a single byte to identificate the elliptic curve for a key
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
  Derivate a new keypair from a seed (retrieved from the local keystore
  and an index representing the number of previous generate keypair.

  The seed generates a master key and an entropy used in the child keys generation.

                                                               / (256 bytes) Next key (next_seed) --> GenKey(next_seed)
                          (256 bytes) Master key  --> HMAC-512
                        /                              Key: Master entropy,
      seed --> HMAC-512                                Data: Master key + index)
                        \
                         (256 bytes) Master entropy



  ## Examples

      iex> {pub, _} = UnirisCore.Crypto.derivate_keypair("myseed", 1)
      iex> {pub10, _} = UnirisCore.Crypto.derivate_keypair("myseed", 10)
      iex> {pub_bis, _} = UnirisCore.Crypto.derivate_keypair("myseed", 1)
      iex> pub != pub10 and pub == pub_bis
      true
  """
  @spec derivate_keypair(
          seed :: binary(),
          index :: non_neg_integer(),
          curve :: __MODULE__.supported_curve()
        ) :: {public_key :: key(), private_key :: key()}
  def derivate_keypair(
        seed,
        index,
        curve \\ Application.get_env(:uniris_core, __MODULE__)[:default_curve]
      )
      when is_binary(seed) and is_integer(index) do
    seed
    |> get_extended_seed(index)
    |> generate_deterministic_keypair(curve)
  end

  @doc """
  Generate the address for the beacon chain for a given transaction subset (two first digit of the address)
  and a date represented as timestamp.

  The date can be either a specific datetime or a specific d@doc ""\"
  Generate the address for the beacon chain for a given transaction subset (two first digit of the address)
  and a date represented as timestamp.

  The date can be either a specific datetime or a specific day
  """
  @spec derivate_beacon_chain_address(subset :: binary(), date :: DateTime.t()) ::
          UnirisCore.Crypto.key()
  def derivate_beacon_chain_address(subset, date = %DateTime{}) when is_binary(subset) do
    Keystore.derivate_beacon_chain_address(subset, DateTime.to_unix(date))
  end

  @doc """
  Store the encrypted daily nonce seed in the keystore by decrypting with the given aes key
  """
  @spec decrypt_and_set_daily_nonce_seed(
          encrypted_seed :: binary(),
          encrypted_aes_key :: binary()
        ) :: :ok
  def decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_aes_key)
      when is_binary(encrypted_seed) and is_binary(encrypted_aes_key) do
    Keystore.decrypt_and_set_daily_nonce_seed(encrypted_seed, encrypted_aes_key)
  end

  @doc """
  Store the encrypted storage nonce in the keystore by decrypting using the last node private key
  """
  @spec decrypt_and_set_storage_nonce(encrypted_nonce :: binary()) :: :ok
  def decrypt_and_set_storage_nonce(encrypted_nonce) when is_binary(encrypted_nonce) do
    Keystore.decrypt_and_set_storage_nonce(encrypted_nonce)
  end

  @doc """
  Encrypt the storage nonce in the keystore using the given public key
  """
  @spec encrypt_storage_nonce(UnirisCore.Crypto.key()) :: binary()
  def encrypt_storage_nonce(public_key) when is_binary(public_key) do
    Keystore.encrypt_storage_nonce(public_key)
  end

  @doc """
  Store the encrypted daily nonce seed in the keystore by decrypting with the given aes key
  """
  @spec decrypt_and_set_node_shared_secrets_transaction_seed(
          encrypted_seed :: binary(),
          encrypted_aes_key :: binary()
        ) :: :ok
  def decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_seed, encrypted_aes_key)
      when is_binary(encrypted_seed) and is_binary(encrypted_aes_key) do
    Keystore.decrypt_and_set_node_shared_secrets_transaction_seed(
      encrypted_seed,
      encrypted_aes_key
    )
  end

  @doc """
  Encrypt the node shared secrets transaction seed located in the keystore using the given aes key
  """
  @spec encrypt_node_shared_secrets_transaction_seed(aes_key :: binary()) :: binary()
  def encrypt_node_shared_secrets_transaction_seed(aes_key) when is_binary(aes_key) do
    Keystore.encrypt_node_shared_secrets_transaction_seed(aes_key)
  end

  defp get_extended_seed(seed, index) do
    <<master_key::binary-32, master_entropy::binary-32>> = :crypto.hmac(:sha512, "", seed)

    <<extended_pv::binary-32, _::binary-32>> =
      :crypto.hmac(:sha512, master_entropy, master_key <> <<index>>)

    extended_pv
  end

  @doc """
  Return the last node public key
  """
  @spec node_public_key() :: UnirisCore.Crypto.key()
  def node_public_key() do
    Keystore.node_public_key()
  end

  @doc """
  Return a node public key by using key derivation from an index

  ## Examples

    iex> pub0 = UnirisCore.Crypto.node_public_key(0)
    iex> pub10 = UnirisCore.Crypto.node_public_key(10)
    iex> pub0_bis = UnirisCore.Crypto.node_public_key(0)
    iex> pub0 != pub10 and pub0 == pub0_bis
    true
  """
  @spec node_public_key(index :: number()) :: UnirisCore.Crypto.key()
  def node_public_key(index) do
    Keystore.node_public_key(index)
  end

  @doc """
  Return the the node shared secrets public key using the node shared secret transaction seed
  """
  @spec node_shared_secrets_public_key(index :: number()) :: UnirisCore.Crypto.key()
  def node_shared_secrets_public_key(index) do
    Keystore.node_shared_secrets_public_key(index)
  end

  @doc """
  Increment the counter for the number of generated node private keys.
  This number is used for the key derivation to detect the latest index.
  """
  @spec increment_number_of_generate_node_keys() :: :ok
  def increment_number_of_generate_node_keys() do
    Keystore.increment_number_of_generate_node_keys()
  end

  @doc """
  Increment the counter for the number of generated node shared secrets private keys.
  This number is used for the key derivation to detect the latest index.
  """
  @spec increment_number_of_generate_node_shared_keys() :: :ok
  def increment_number_of_generate_node_shared_keys() do
    Keystore.increment_number_of_generate_node_shared_secrets_keys()
  end

  @doc """
  Return the number of node keys after incrementation
  """
  @spec number_of_node_keys() :: non_neg_integer()
  def number_of_node_keys() do
    Keystore.number_of_node_keys()
  end

  @doc """
  Return the number of node shared secrets keys after incrementation
  """
  @spec number_of_node_shared_secrets_keys() :: non_neg_integer()
  def number_of_node_shared_secrets_keys() do
    Keystore.number_of_node_shared_secrets_keys()
  end

  @doc """
  Generate a keypair in a deterministic way using a seed

  ## Examples

      iex> {pub, _} = UnirisCore.Crypto.generate_deterministic_keypair("myseed")
      iex> pub
      <<0, 195, 217, 87, 74, 44, 143, 133, 202, 49, 24, 21, 172, 125, 120, 229, 214,
      229, 203, 0, 171, 137, 3, 53, 26, 206, 212, 108, 55, 78, 175, 52, 104>>

      iex> {pub, _} = UnirisCore.Crypto.generate_deterministic_keypair("myseed", :secp256r1)
      iex> pub
      <<1, 4, 71, 234, 56, 77, 247, 36, 202, 205, 0, 115, 85, 40, 74, 90, 107, 180,
      162, 184, 168, 248, 179, 160, 69, 68, 159, 128, 0, 23, 81, 29, 122, 89, 51,
      182, 115, 31, 213, 158, 244, 116, 92, 197, 246, 196, 55, 27, 8, 205, 62, 39,
      55, 227, 59, 94, 246, 213, 26, 22, 150, 137, 167, 23, 69, 144>>

  """
  @spec generate_deterministic_keypair(
          seed :: binary(),
          curve :: __MODULE__.supported_curve()
        ) :: {public_key :: key(), private_key :: key()}
  def generate_deterministic_keypair(
        seed,
        curve \\ Application.get_env(:uniris_core, __MODULE__)[:default_curve]
      )
      when is_binary(seed) do
    do_generate_deterministic_keypair(curve, seed)
  end

  defp do_generate_deterministic_keypair(:ed25519, seed) do
    seed
    |> Ed25519.generate_keypair()
    |> ID.identify_keypair(ID.id_from_curve(:ed25519))
  end

  defp do_generate_deterministic_keypair(curve, seed) do
    curve
    |> ECDSA.generate_keypair(seed)
    |> ID.identify_keypair(ID.id_from_curve(curve))
  end

  @doc """
  Sign data.

  The first byte of the private key identifies the curve and the signature algorithm to use

  ## Examples

      iex> {pub, pv} = UnirisCore.Crypto.generate_deterministic_keypair("myseed")
      iex> UnirisCore.Crypto.sign("myfakedata", pv)
      <<240, 207, 59, 29, 236, 164, 157, 87, 84, 62, 177, 26, 76, 69, 209, 125, 110,
      136, 168, 113, 112, 243, 155, 254, 59, 214, 193, 191, 112, 55, 194, 220, 2,
      190, 0, 1, 214, 104, 252, 133, 3, 112, 19, 27, 129, 231, 237, 59, 174, 4, 82,
      210, 110, 204, 219, 237, 197, 26, 140, 63, 97, 67, 27, 8>>
  """
  @spec sign(data :: any(), private_key :: binary()) :: signature :: binary()
  def sign(data, <<curve_id::8, key::binary>>) when is_binary(data) do
    ID.curve_from_id(curve_id)
    |> do_sign(data, key)
  end

  def sign(data, key), do: sign(:erlang.term_to_binary(data), key)

  def do_sign(:ed25519, data, key), do: Ed25519.sign(key, data)
  def do_sign(curve, data, key), do: ECDSA.sign(curve, key, data)

  @doc """
  Sign the data with the last node private key
  """
  @spec sign_with_node_key(data :: binary()) :: binary()
  def sign_with_node_key(data) when is_binary(data) do
    Keystore.sign_with_node_key(data)
  end

  def sign_with_node_key(data) do
    sign_with_node_key(:erlang.term_to_binary(data))
  end

  @doc """
  Sign the data with the private key at the given index.

  """
  @spec sign_with_node_key(data :: binary(), index :: binary()) :: binary()
  def sign_with_node_key(data, index) when is_binary(data) and is_number(index) do
    Keystore.sign_with_node_key(data, index)
  end

  def sign_with_node_key(data, index) do
    sign_with_node_key(:erlang.term_to_binary(data), index)
  end

  @doc """
  Sign the data with the node shared secrets transaction seed
  """
  @spec sign_with_node_shared_secrets_key(data :: binary()) :: binary()
  def sign_with_node_shared_secrets_key(data) when is_binary(data) do
    Keystore.sign_with_node_shared_secrets_key(data)
  end

  def sign_with_node_shared_secrets_key(data) do
    sign_with_node_shared_secrets_key(:erlang.term_to_binary(data))
  end

  @doc """
  Sign the data with the node shared secrets transaction seed
  """
  @spec sign_with_node_shared_secrets_key(data :: binary(), index :: non_neg_integer()) ::
          binary()
  def sign_with_node_shared_secrets_key(data, index) when is_binary(data) and is_integer(index) do
    Keystore.sign_with_node_shared_secrets_key(data, index)
  end

  def sign_with_node_shared_secrets_key(data, index) do
    sign_with_node_shared_secrets_key(:erlang.term_to_binary(data), index)
  end

  @doc """
  Verify a signature.

  The first byte of the public key identifies the curve and the verification algorithl to use.

  ## Examples

      iex> {pub, pv} = UnirisCore.Crypto.generate_deterministic_keypair("myseed")
      iex> sig = UnirisCore.Crypto.sign("myfakedata", pv)
      iex> UnirisCore.Crypto.verify(sig, "myfakedata", pub)
      true

  Returns an error when the signature is invalid
      iex> {pub, _} = UnirisCore.Crypto.generate_deterministic_keypair("myseed")
      iex> sig = <<1, 48, 69, 2, 33, 0, 185, 231, 7, 86, 207, 253, 8, 230, 199, 94, 251, 33, 42, 172, 95, 93, 7, 209, 175, 69, 216, 121, 239, 24, 17, 21, 41, 129, 255, 49, 153, 116, 2, 32, 85, 1, 212, 69, 182, 98, 174, 213, 79, 154, 69, 84, 149, 126, 169, 44, 98, 64, 21, 211, 20, 235, 165, 97, 61, 8, 239, 194, 196, 177, 46, 199>>
      iex> UnirisCore.Crypto.verify(sig, "myfakedata", pub)
      false
  """
  @spec verify(signature :: binary(), data :: any(), public_key :: key()) :: boolean()
  def verify(
        sig,
        data,
        <<curve_id::8, key::binary>> = _public_key
      )
      when is_binary(data) do
    curve = ID.curve_from_id(curve_id)
    do_verify(curve, key, data, sig)
  end

  def verify(sig, data, key),
    do: verify(sig, :erlang.term_to_binary(data), key)

  defp do_verify(:ed25519, key, data, sig), do: Ed25519.verify(key, data, sig)
  defp do_verify(curve, key, data, sig), do: ECDSA.verify(curve, key, data, sig)

  @doc """
  Encrypts data using public key authenticated encryption (ECIES).

  Ephemeral and random ECDH key pair is generated which is used to generate shared
  secret with the given public key(transformed to ECDH public key).

  Based on this secret, KDF derivate keys are used to create an authenticated symmetric encryption.

  ## Examples

      ```
      pub = {pub, _} = UnirisCore.Crypto.generate_deterministic_keypair("myseed")
      UnirisCore.Crypto.ec_encrypt("myfakedata", pub)
      <<0, 0, 0, 0, 58, 138, 57, 196, 76, 95, 222, 131, 128, 248, 50, 146, 221, 145,
      152, 20, 45, 164, 221, 166, 242, 172, 237, 36, 238, 150, 238, 127, 53, 160,
      43, 159, 91, 6, 234, 99, 42, 174, 193, 165, 203, 74, 99, 179, 225, 137, 159,
      30, 79, 81, 24, 47, 27, 175, 252, 252, 64, 11, 207>>
      ```
  """
  @spec ec_encrypt(message :: term() | binary(), public_key :: key()) :: binary()
  def ec_encrypt(message, <<curve_id::8, key::binary>> = _public_key) when is_binary(message) do
    curve = ID.curve_from_id(curve_id)
    do_ec_encrypt(curve, message, key)
  end

  defp do_ec_encrypt(:ed25519, message, public_key), do: Ed25519.encrypt(public_key, message)
  defp do_ec_encrypt(curve, message, public_key), do: ECDSA.encrypt(curve, public_key, message)

  @doc """
  Decrypt a cipher using public key authenticated encryption (ECIES).

  A cipher contains a generated ephemeral random public key coupled with an authentication tag.

  Private key is transformed to ECDH to compute a shared secret with this random public key.

  Based on this secret, KDF derivate keys are used to create an authenticated symmetric decryption.

  Before the decryption, the authentication will be checked to ensure the given private key
  has the right to decrypt this data.

  ## Examples

      iex> cipher = <<0, 0, 0, 58, 16, 25, 106, 181, 34, 80, 25, 136, 170, 141, 8, 112, 178, 140, 1, 180, 192, 35, 141, 241, 149, 179, 111, 154, 57, 244, 88, 102, 57, 95, 240, 17, 121, 194, 181, 224, 45, 68, 115, 111, 19, 136, 156, 91, 231, 53, 171, 79, 231, 226, 122, 76, 38, 129, 81, 79, 43, 133>>
      iex> {pub, pv} = UnirisCore.Crypto.generate_deterministic_keypair("myseed")
      iex> UnirisCore.Crypto.ec_decrypt!(cipher, pv)
      "myfakedata"

  Invalid message to decrypt or key return an error:

      ```
      UnirisCore.Crypto.generate_deterministic_keypair("myseed", :node)
      UnirisCore.Crypto.ec_decrypt!(<<0, 0, 0>>, :node)
      ** (RuntimeError) Decryption failed
      ```
  """
  @spec ec_decrypt!(cipher :: binary(), private_key :: key()) :: term()
  def ec_decrypt!(cipher, _private_key = <<curve_id::8, key::binary>>) when is_binary(cipher) do
    do_ec_decrypt!(ID.curve_from_id(curve_id), cipher, key)
  end

  @doc """
  Decrypt the cipher using last node private key
  """
  @spec ec_decrypt_with_node_key!(cipher :: binary()) :: term()
  def ec_decrypt_with_node_key!(cipher) do
    Keystore.decrypt_with_node_key!(cipher)
  end

  @doc """
  Decrypt the cipher using last node private key
  """
  @spec ec_decrypt_with_node_key!(cipher :: binary(), index :: non_neg_integer()) :: term()
  def ec_decrypt_with_node_key!(cipher, index) do
    Keystore.decrypt_with_node_key!(cipher, index)
  end

  defp do_ec_decrypt!(:ed25519, cipher, key), do: Ed25519.decrypt(key, cipher)
  defp do_ec_decrypt!(curve, cipher, key), do: ECDSA.decrypt(curve, key, cipher)

  @doc """
  Encrypt a data using AES authenticated encryption.
  """
  @spec aes_encrypt(data :: term(), key :: binary) :: aes_cipher

  @spec aes_encrypt(data :: binary(), key :: binary) :: aes_cipher
  def aes_encrypt(data, <<key::binary-32>>) when is_binary(data) do
    iv = :crypto.strong_rand_bytes(12)
    {cipher, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, data, "", true)
    iv <> tag <> cipher
  end

  @doc """
  Decrypt a ciphertext using the AES authenticated decryption.

  ## Examples

      iex> key = <<234, 210, 202, 129, 91, 76, 68, 14, 17, 212, 197, 49, 66, 168, 52, 111, 176,
      ...> 182, 227, 156, 5, 32, 24, 105, 41, 152, 67, 191, 187, 209, 101, 36>>
      iex> ciphertext = UnirisCore.Crypto.aes_encrypt("sensitive data", key)
      iex> UnirisCore.Crypto.aes_decrypt!(ciphertext, key)
      "sensitive data"

  Return an error when the key is invalid

      ```
      ciphertext = UnirisCore.Crypto.aes_encrypt("sensitive data", :crypto.strong_rand_bytes(32))
      UnirisCore.Crypto.aes_decrypt!(ciphertext, :crypto.strong_rand_bytes(32))
      ** (RuntimeError) Decryption failed
      ```

  """
  @spec aes_decrypt!(cipher :: aes_cipher, key :: binary) :: term()
  def aes_decrypt!(<<iv::8*12, tag::8*16, cipher::binary>>, <<key::binary-32>>) do
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

  @doc """
  Hash a data.

  A first-byte prepends each hash to indicate the algorithm used.

  ## Examples

      iex> UnirisCore.Crypto.hash("myfakedata", :sha256)
      <<0, 78, 137, 232, 16, 150, 235, 9, 199, 74, 41, 189, 246, 110, 65, 252, 17,
      139, 109, 23, 172, 84, 114, 35, 202, 102, 41, 167, 23, 36, 230, 159, 35>>

      iex> UnirisCore.Crypto.hash("myfakedata", :blake2b)
      <<4, 244, 16, 24, 144, 16, 67, 113, 164, 214, 115, 237, 113, 126, 130, 76, 128,
      99, 78, 223, 60, 179, 158, 62, 239, 245, 85, 4, 156, 10, 2, 94, 95, 19, 166,
      170, 147, 140, 117, 1, 169, 132, 113, 202, 217, 193, 56, 112, 193, 62, 134,
      145, 233, 114, 41, 228, 164, 180, 225, 147, 2, 33, 192, 42, 184>>

      iex> UnirisCore.Crypto.hash("myfakedata", :sha3_256)
      <<2, 157, 219, 54, 234, 186, 251, 4, 122, 216, 105, 185, 228, 211, 94, 44, 94,
      104, 147, 182, 189, 45, 28, 219, 218, 236, 19, 66, 87, 121, 240, 249, 218>>
  """
  @spec hash(data :: map() | binary(), algo :: supported_hash()) ::
          hash() | {:error, :invalid_hash_algo}
  def hash(data, algo \\ Application.get_env(:uniris_core, __MODULE__)[:default_hash])

  def hash(data, algo) when is_binary(data) do
    hash_algo_id = ID.id_from_hash(algo)

    do_hash(data, algo)
    |> ID.identify_hash(hash_algo_id)
  end

  def hash(data, algo),
    do: hash(:erlang.term_to_binary(data), algo)

  defp do_hash(data, :sha256), do: :crypto.hash(:sha256, data)
  defp do_hash(data, :sha512), do: :crypto.hash(:sha512, data)
  defp do_hash(data, :sha3_256), do: :crypto.hash(:sha3_256, data)
  defp do_hash(data, :sha3_512), do: :crypto.hash(:sha3_512, data)
  defp do_hash(data, :blake2b), do: :crypto.hash(:blake2b, data)

  @spec hash_with_daily_nonce(data :: binary()) :: binary()
  def hash_with_daily_nonce(data) do
    Keystore.hash_with_daily_nonce(data)
  end

  @spec hash_with_storage_nonce(data :: binary()) :: binary()
  def hash_with_storage_nonce(data) do
    Keystore.hash_with_storage_nonce(data)
  end

  @doc """
  Check the validity of a public key.

  The first byte of the public key identifies the curve and the validation rules to apply.

  ## Examples

      iex> {pub, _} = UnirisCore.Crypto.generate_deterministic_keypair("myseed")
      iex> UnirisCore.Crypto.valid_public_key?(pub)
      true

      iex> {pub, _} = UnirisCore.Crypto.generate_deterministic_keypair("myseed", :secp256r1)
      iex> UnirisCore.Crypto.valid_public_key?(pub)
      true

  Invalid size of public key return an error:

      iex> UnirisCore.Crypto.valid_public_key?(<<1,0>>)
      false
  """
  @spec valid_public_key?(key()) :: boolean()
  def valid_public_key?(<<curve_id::8, key::binary>>) do
    curve = ID.curve_from_id(curve_id)
    do_valid_public_key?(curve, key)
  end

  def valid_public_key?(_), do: false

  defp do_valid_public_key?(:ed25519, key) when byte_size(key) == 32 do
    true
  end

  defp do_valid_public_key?(_, key) when byte_size(key) == 65 do
    true
  end

  defp do_valid_public_key?(_, _) do
    false
  end

  @doc """
  Checks if a hash is valid

  ## Examples

      iex> hash = UnirisCore.Crypto.hash("mydata", :sha256)
      iex> UnirisCore.Crypto.valid_hash?(hash)
      true

      iex> UnirisCore.Crypto.valid_hash?("myfakesha256")
      false

      iex> UnirisCore.Crypto.valid_hash?(:crypto.strong_rand_bytes(32))
      false
  """
  @spec valid_hash?(hash()) :: boolean()
  def valid_hash?(<<0::8, hash::binary>>), do: byte_size(hash) == 32
  def valid_hash?(<<1::8, hash::binary>>), do: byte_size(hash) == 64
  def valid_hash?(<<2::8, hash::binary>>), do: byte_size(hash) == 32
  def valid_hash?(<<3::8, hash::binary>>), do: byte_size(hash) == 64
  def valid_hash?(<<4::8, hash::binary>>), do: byte_size(hash) == 64
  def valid_hash?(_hash), do: false
end
