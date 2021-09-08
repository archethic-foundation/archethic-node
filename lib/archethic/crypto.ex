defmodule ArchEthic.Crypto do
  @moduledoc """
  Provide cryptographic operations for ArchEthic network.

  An algorithm identification is produced by prepending keys and hashes.
  This identification helps to determine which algorithm/implementation to use in key generation and hashing.


   ```
   Ed25519  Software  Public key
        |  /           |
        |  |   |-------|  
        |  |   |
      <<0, 0, 106, 58, 193, 73, 144, 121, 104, 101, 53, 140, 125, 240, 52, 222, 35, 181,
      13, 81, 241, 114, 227, 205, 51, 167, 139, 100, 176, 111, 68, 234, 206, 72>>

       NIST P-256  Software   Public key
        |  |-------|         |
        |  |  |--------------|
        |  |  |
      <<1, 0, 4, 7, 161, 46, 148, 183, 43, 175, 150, 13, 39, 6, 158, 100, 2, 46, 167,
       101, 222, 82, 108, 56, 71, 28, 192, 188, 104, 154, 182, 87, 11, 218, 58, 107,
      222, 154, 48, 222, 193, 176, 88, 174, 1, 6, 154, 72, 28, 217, 222, 147, 106,
      73, 150, 128, 209, 93, 99, 115, 17, 39, 96, 47, 203, 104, 34>>
  ```


  Some functions rely on software implementations such as hashing, signature verification.
  Other can rely on hardware or software as a configuration choice to generate keys, sign or decrypt data.
  According to the implementation, keys can be stored and regenerated on the fly
  """

  alias __MODULE__.ECDSA
  alias __MODULE__.Ed25519
  alias __MODULE__.ID
  alias __MODULE__.NodeKeystore
  alias __MODULE__.SharedSecretsKeystore

  alias ArchEthic.SharedSecrets

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Key

  alias ArchEthic.Utils

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
  List of the supported key origins
  """
  @type supported_origin :: :software | :tpm

  @typedoc """
  Binary representing a hash prepend by a single byte to identify the algorithm of the generated hash
  """
  @type versioned_hash :: <<_::8, _::_*8>>

  @typedoc """
  Binary representing a key prepend by two bytes:
  - to identify the elliptic curve for a key
  - to identify the origin of the key derivation (software, TPM)
  """
  @type key :: <<_::16, _::_*8>>

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

  @certification_public_keys Application.compile_env(
                               :archethic,
                               [__MODULE__, :root_ca_public_keys],
                               []
                             )

  @doc """
  Derive a new keypair from a seed (retrieved from the local keystore
  and an index representing the number of previous generate keypair.

  The seed generates a master key and an entropy used in the child keys generation.

                                                               / (256 bytes) Next private key
                          (256 bytes) Master key  --> HMAC-512
                        /                              Key: Master entropy,
      seed --> HASH-512                                Data: Master key + index)
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
        curve \\ Application.get_env(:archethic, __MODULE__)[:default_curve]
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
  @spec derive_beacon_chain_address(subset :: binary(), date :: DateTime.t(), boolean()) ::
          binary()
  def derive_beacon_chain_address(subset, date = %DateTime{}, summary? \\ false)
      when is_binary(subset) do
    subset
    |> derive_beacon_keypair(date, summary?)
    |> elem(0)
    |> hash()
  end

  @doc """
  Derive a keypair for beacon transaction based on the subset and the date
  """
  @spec derive_beacon_keypair(binary(), DateTime.t(), boolean()) :: {key(), key()}
  def derive_beacon_keypair(subset, date = %DateTime{}, summary? \\ false) do
    summary_byte = if summary?, do: 1, else: 0

    derive_keypair(
      :persistent_term.get(:storage_nonce),
      hash(["beacon", subset, <<DateTime.to_unix(date)::32, summary_byte::8>>])
    )
  end

  @doc """
  Derive a keypair for oracle transaction based on a data and a chain size
  """
  @spec derive_oracle_keypair(DateTime.t(), non_neg_integer()) :: {key(), key()}
  def derive_oracle_keypair(date = %DateTime{}, size) when is_integer(size) and size >= 0 do
    derive_keypair(
      storage_nonce(),
      hash([
        "oracle",
        <<DateTime.to_unix(date)::32, size::32>>
      ])
    )
  end

  @doc """
  Derive a oracle transaction address based on a subset and chain size
  """
  @spec derive_oracle_address(DateTime.t(), non_neg_integer()) :: versioned_hash()
  def derive_oracle_address(date = %DateTime{}, size) when is_integer(size) and size >= 0 do
    date
    |> derive_oracle_keypair(size)
    |> elem(0)
    |> hash()
  end

  @doc """
  Store the encrypted secrets in the keystore by decrypting them with the given secret key
  """
  @spec unwrap_secrets(
          encrypted_secrets :: binary(),
          encrypted_secret_key :: binary(),
          date :: DateTime.t()
        ) :: :ok | :error
  def unwrap_secrets(encrypted_secrets, encrypted_key, timestamp = %DateTime{})
      when is_binary(encrypted_secrets) and is_binary(encrypted_key) do
    SharedSecretsKeystore.unwrap_secrets(encrypted_secrets, encrypted_key, timestamp)
  end

  @doc """
  Store the storage nonce in memory by decrypting it using the last node private key
  """
  @spec decrypt_and_set_storage_nonce(encrypted_nonce :: binary()) :: :ok
  def decrypt_and_set_storage_nonce(encrypted_nonce) when is_binary(encrypted_nonce) do
    storage_nonce = ec_decrypt_with_last_node_key!(encrypted_nonce)
    storage_nonce_path = storage_nonce_filepath()
    :ok = File.mkdir_p!(Path.dirname(storage_nonce_path))
    :ok = File.write(storage_nonce_path, storage_nonce, [:write])
    :ok = :persistent_term.put(:storage_nonce, storage_nonce)
    Logger.info("Storage nonce stored")
  end

  @doc """
  Encrypt the storage nonce from memory using the given public key
  """
  @spec encrypt_storage_nonce(key()) :: binary()
  def encrypt_storage_nonce(public_key) when is_binary(public_key) do
    ec_encrypt(:persistent_term.get(:storage_nonce), public_key)
  end

  @doc """
  Encrypt the node shared secrets transaction seed located in the keystore using the given secret key
  """
  @spec wrap_secrets(key :: binary()) ::
          {enc_transaction_seed :: binary(), enc_network_pool_seed :: binary()}
  defdelegate wrap_secrets(aes_key), to: SharedSecretsKeystore

  defp get_extended_seed(seed, additional_data) do
    <<master_key::binary-32, master_entropy::binary-32>> = :crypto.hash(:sha512, seed)

    <<extended_pv::binary-32, _::binary-32>> =
      :crypto.mac(:hmac, :sha512, master_entropy, <<master_key::binary, additional_data::binary>>)

    extended_pv
  end

  @doc """
  Return the last node public key
  """
  @spec last_node_public_key() :: key()
  defdelegate last_node_public_key, to: NodeKeystore, as: :last_public_key

  @doc """
  Return the previous node public key
  """
  defdelegate previous_node_public_key, to: NodeKeystore, as: :previous_public_key

  @doc """
  Return the first node public key
  """
  @spec first_node_public_key() :: key()
  defdelegate first_node_public_key, to: NodeKeystore, as: :first_public_key

  @doc """
  Return the next node public key
  """
  @spec next_node_public_key() :: key()
  defdelegate next_node_public_key, to: NodeKeystore, as: :next_public_key

  @doc """
  Return the the node shared secrets public key using the node shared secret transaction seed
  """
  @spec node_shared_secrets_public_key(index :: number()) :: key()
  defdelegate node_shared_secrets_public_key(index), to: SharedSecretsKeystore

  @doc """
  Return the the network pool public key using the network pool transaction seed
  """
  @spec network_pool_public_key(index :: number()) :: key()
  defdelegate network_pool_public_key(index), to: SharedSecretsKeystore

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
  Return the number of node shared secrets keys after incrementation
  """
  @spec number_of_node_shared_secrets_keys() :: non_neg_integer()
  defdelegate number_of_node_shared_secrets_keys,
    to: SharedSecretsKeystore,
    as: :get_node_shared_key_index

  @doc """
  Return the number of network pool keys after incrementation
  """
  @spec number_of_network_pool_keys() :: non_neg_integer()
  defdelegate number_of_network_pool_keys,
    to: SharedSecretsKeystore,
    as: :get_network_pool_key_index

  @doc """
  Generate a keypair in a deterministic way using a seed

  ## Examples

      iex> {pub, _} = Crypto.generate_deterministic_keypair("myseed")
      iex> pub
      <<0, 0, 91, 43, 89, 132, 233, 51, 190, 190, 189, 73, 102, 74, 55, 126, 44, 117, 50,
      36, 220, 249, 242, 73, 105, 55, 83, 190, 3, 75, 113, 199, 247, 165>>

      iex> {pub, _} = Crypto.generate_deterministic_keypair("myseed", :secp256r1)
      iex> pub
      <<1, 0, 4, 140, 235, 188, 198, 146, 160, 92, 132, 81, 177, 113, 230, 39, 220, 122,
      112, 231, 18, 90, 66, 156, 47, 54, 192, 141, 44, 45, 223, 115, 28, 30, 48,
      105, 253, 171, 105, 87, 148, 108, 150, 86, 128, 28, 102, 163, 51, 28, 57, 33,
      133, 109, 49, 202, 92, 184, 138, 187, 26, 123, 45, 5, 94, 180, 250>>

  """
  @spec generate_deterministic_keypair(
          seed :: binary(),
          curve :: supported_curve()
        ) :: {public_key :: key(), private_key :: key()}
  def generate_deterministic_keypair(
        seed,
        curve \\ Application.get_env(:archethic, __MODULE__)[:default_curve]
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
  Generate random keypair
  """
  @spec generate_random_keypair(supported_curve()) :: {public_key :: key(), private_key :: key()}
  def generate_random_keypair(
        curve \\ Application.get_env(:archethic, __MODULE__)[:default_curve]
      ) do
    generate_deterministic_keypair(:crypto.strong_rand_bytes(32), curve)
  end

  @doc """
  Sign data.

  The first byte of the private key identifies the curve and the signature algorithm to use

  ## Examples

      iex> {_pub, pv} = Crypto.generate_deterministic_keypair("myseed")
      iex> Crypto.sign("myfakedata", pv)
      <<220, 110, 7, 254, 119, 249, 124, 5, 24, 45, 224, 214, 60, 49, 223, 238, 47,
      58, 91, 108, 33, 18, 230, 144, 178, 191, 236, 235, 188, 32, 224, 129, 47, 18,
      216, 220, 32, 82, 252, 20, 55, 2, 204, 94, 73, 37, 44, 220, 33, 26, 44, 124,
      20, 44, 255, 249, 77, 201, 97, 108, 213, 107, 134, 9>>
  """
  @spec sign(data :: iodata(), private_key :: binary()) :: signature :: binary()
  def sign(data, _private_key = <<curve_id::8, _::8, key::binary>>)
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
  @spec sign_with_last_node_key(data :: iodata() | bitstring() | [bitstring]) :: binary()
  def sign_with_last_node_key(data) when is_bitstring(data) or is_list(data) do
    data
    |> Utils.wrap_binary()
    |> NodeKeystore.sign_with_last_key()
  end

  @doc """
  Sign with the previous node key
  """
  @spec sign_with_previous_node_key(data :: iodata() | bitstring() | [bitstring]) :: binary()
  def sign_with_previous_node_key(data) when is_bitstring(data) or is_list(data) do
    data
    |> Utils.wrap_binary()
    |> NodeKeystore.sign_with_previous_key()
  end

  @doc """
  Sign the data with the first node private key
  """
  def sign_with_first_node_key(data) do
    data
    |> Utils.wrap_binary()
    |> NodeKeystore.sign_with_first_key()
  end

  @doc """
  Sign the data with the node shared secrets transaction seed
  """
  @spec sign_with_node_shared_secrets_key(data :: iodata()) :: binary()
  def sign_with_node_shared_secrets_key(data) when is_bitstring(data) or is_list(data) do
    data
    |> Utils.wrap_binary()
    |> SharedSecretsKeystore.sign_with_node_shared_secrets_key()
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
    |> SharedSecretsKeystore.sign_with_node_shared_secrets_key(index)
  end

  @doc """
  Sign the data with the network pool transaction seed
  """
  @spec sign_with_network_pool_key(data :: iodata()) :: binary()
  def sign_with_network_pool_key(data) when is_bitstring(data) or is_list(data) do
    data
    |> Utils.wrap_binary()
    |> SharedSecretsKeystore.sign_with_network_pool_key()
  end

  @doc """
  Sign the data with the network pool transaction seed
  """
  @spec sign_with_network_pool_key(data :: iodata(), index :: non_neg_integer()) ::
          binary()
  def sign_with_network_pool_key(data, index)
      when (is_bitstring(data) or is_list(data)) and is_integer(index) and index >= 0 do
    data
    |> Utils.wrap_binary()
    |> SharedSecretsKeystore.sign_with_network_pool_key(index)
  end

  @doc """
  Sign data with the daily nonce stored in the keystore
  """
  @spec sign_with_daily_nonce_key(data :: iodata(), DateTime.t()) :: binary()
  defdelegate sign_with_daily_nonce_key(data, timestamp), to: SharedSecretsKeystore

  @doc """
  Verify a signature.

  The first byte of the public key identifies the curve and the verification algorithm to use.

  ## Examples

      iex> {pub, pv} = Crypto.generate_deterministic_keypair("myseed")
      iex> sig = Crypto.sign("myfakedata", pv)
      iex> Crypto.verify?(sig, "myfakedata", pub)
      true

  Returns false when the signature is invalid
      iex> {pub, _} = Crypto.generate_deterministic_keypair("myseed")
      iex> sig = <<1, 48, 69, 2, 33, 0, 185, 231, 7, 86, 207, 253, 8, 230, 199, 94, 251, 33, 42, 172, 95, 93, 7, 209, 175, 69, 216, 121, 239, 24, 17, 21, 41, 129, 255, 49, 153, 116, 2, 32, 85, 1, 212, 69, 182, 98, 174, 213, 79, 154, 69, 84, 149, 126, 169, 44, 98, 64, 21, 211, 20, 235, 165, 97, 61, 8, 239, 194, 196, 177, 46, 199>>
      iex> Crypto.verify?(sig, "myfakedata", pub)
      false
  """
  @spec verify?(
          signature :: binary(),
          data :: iodata() | bitstring() | [bitstring],
          public_key :: key()
        ) ::
          boolean()
  def verify?(
        sig,
        data,
        <<curve_id::8, _::8, key::binary>> = _public_key
      )
      when is_bitstring(data) or is_list(data) do
    curve_id
    |> ID.to_curve()
    |> do_verify?(key, Utils.wrap_binary(data), sig)
  end

  defp do_verify?(:ed25519, key, data, sig), do: Ed25519.verify?(key, data, sig)
  defp do_verify?(curve, key, data, sig), do: ECDSA.verify?(curve, key, data, sig)

  @doc """
  Encrypts data using public key authenticated encryption (ECIES).

  Ephemeral and random ECDH key pair is generated which is used to generate shared
  secret with the given public key(transformed to ECDH public key).

  Based on this secret, KDF derive keys are used to create an authenticated symmetric encryption.

  ## Examples

      ```
      {pub, _} = Crypto.generate_deterministic_keypair("myseed")
      Crypto.ec_encrypt("myfakedata", pub)
      <<20, 95, 27, 87, 71, 195, 100, 164, 225, 201, 163, 220, 15, 111, 201, 224, 41,
      34, 143, 78, 201, 109, 157, 196, 108, 109, 155, 91, 239, 118, 23, 100, 161,
      195, 39, 117, 148, 223, 182, 23, 1, 197, 205, 93, 239, 19, 27, 248, 168, 107,
      40, 0, 68, 224, 177, 110, 180, 24>>
      ```
  """
  @spec ec_encrypt(message :: binary(), public_key :: key()) :: binary()
  def ec_encrypt(message, <<curve_id::8, _::8, public_key::binary>> = _public_key)
      when is_binary(message) do
    curve = ID.to_curve(curve_id)

    {ephemeral_public_key, ephemeral_private_key} = generate_ephemeral_encryption_keys(curve)

    # Derivate secret using ECDH with the given public key and the ephemeral private key
    shared_key =
      case curve do
        :ed25519 ->
          x25519_pk = Ed25519.convert_to_x25519_public_key(public_key)
          :crypto.compute_key(:ecdh, x25519_pk, ephemeral_private_key, :x25519)

        _ ->
          :crypto.compute_key(:ecdh, public_key, ephemeral_private_key, curve)
      end

    # Generate keys for the AES authenticated encryption
    {iv, aes_key} = derivate_secrets(shared_key)

    {cipher, tag} = aes_auth_encrypt(iv, aes_key, message)

    # Encode the cipher within the ephemeral public key, the authentication tag
    <<ephemeral_public_key::binary, tag::binary, cipher::binary>>
  end

  defp generate_ephemeral_encryption_keys(:ed25519), do: :crypto.generate_key(:ecdh, :x25519)
  defp generate_ephemeral_encryption_keys(curve), do: :crypto.generate_key(:ecdh, curve)

  defp derivate_secrets(dh_key) do
    pseudorandom_key = :crypto.hash(:sha256, dh_key)
    iv = binary_part(:crypto.mac(:hmac, :sha256, pseudorandom_key, "0"), 0, 32)
    aes_key = binary_part(:crypto.mac(:hmac, :sha256, iv, "1"), 0, 32)
    {iv, aes_key}
  end

  defp aes_auth_encrypt(iv, key, data),
    do: :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, data, "", true)

  defp aes_auth_decrypt(iv, key, cipher, tag),
    do: :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, cipher, "", tag, false)

  @doc """
  Decrypt a cipher using public key authenticated encryption (ECIES).

  A cipher contains a generated ephemeral random public key coupled with an authentication tag.

  Private key is transformed to ECDH to compute a shared secret with this random public key.

  Based on this secret, KDF derive keys are used to create an authenticated symmetric decryption.

  Before the decryption, the authentication will be checked to ensure the given private key
  has the right to decrypt this data.

  ## Examples

      iex> cipher = <<20, 95, 27, 87, 71, 195, 100, 164, 225, 201, 163, 220, 15, 111, 201, 224, 41,
      ...> 34, 143, 78, 201, 109, 157, 196, 108, 109, 155, 91, 239, 118, 23, 100, 161,
      ...> 195, 39, 117, 148, 223, 182, 23, 1, 197, 205, 93, 239, 19, 27, 248, 168, 107,
      ...> 40, 0, 68, 224, 177, 110, 180, 24>>
      iex> {_pub, pv} = Crypto.generate_deterministic_keypair("myseed")
      iex> ArchEthic.Crypto.ec_decrypt!(cipher, pv)
      "myfakedata"

  Invalid message to decrypt or key return an error:

      ```
      iex> cipher = <<20, 95, 27, 87, 71, 195, 100, 164, 225, 201, 163, 220, 15, 111, 201, 224, 41,
      ...> 34, 143, 78, 201, 109, 157, 196, 108, 109, 155, 91, 239, 118, 23, 100, 161,
      ...> 195, 39, 117, 148, 223, 182, 23, 1, 197, 205, 93, 239, 19, 27, 248, 168, 107,
      ...> 40, 0, 68, 224, 177, 110, 180, 24>>
      iex> {_, pv} = Crypto.generate_deterministic_keypair("otherseed")
      iex> Crypto.ec_decrypt!(cipher, pv)
      ** (RuntimeError) Decryption failed
      ```
  """
  @spec ec_decrypt!(encoded_cipher :: binary(), private_key :: key()) :: binary()
  def ec_decrypt!(encoded_cipher, private_key)
      when is_binary(encoded_cipher) and is_binary(private_key) do
    case ec_decrypt(encoded_cipher, private_key) do
      {:error, :decryption_failed} ->
        raise "Decryption failed"

      {:ok, data} ->
        data
    end
  end

  @doc """

  ## Examples

      iex> cipher = <<20, 95, 27, 87, 71, 195, 100, 164, 225, 201, 163, 220, 15, 111, 201, 224, 41,
      ...> 34, 143, 78, 201, 109, 157, 196, 108, 109, 155, 91, 239, 118, 23, 100, 161,
      ...> 195, 39, 117, 148, 223, 182, 23, 1, 197, 205, 93, 239, 19, 27, 248, 168, 107,
      ...> 40, 0, 68, 224, 177, 110, 180, 24>>
      iex> {_pub, pv} = Crypto.generate_deterministic_keypair("myseed")
      iex> {:ok, "myfakedata"} = Crypto.ec_decrypt(cipher, pv)

  Invalid message to decrypt return an error:

      iex> cipher = <<20, 95, 27, 87, 71, 195, 100, 164, 225, 201, 163, 220, 15, 111, 201, 224, 41,
      ...> 34, 143, 78, 201, 109, 157, 196, 108, 109, 155, 91, 239, 118, 23, 100, 161,
      ...> 195, 39, 117, 148, 223, 182, 23, 1, 197, 205, 93, 239, 19, 27, 248, 168, 107,
      ...> 40, 0, 68, 224, 177, 110, 180, 24>>
      iex> {_, pv} = Crypto.generate_deterministic_keypair("otherseed")
      iex> Crypto.ec_decrypt(cipher, pv)
      {:error, :decryption_failed}
  """
  @spec ec_decrypt(cipher :: binary(), private_key :: key()) ::
          {:ok, binary()} | {:error, :decryption_failed}
  def ec_decrypt(
        encoded_cipher,
        _private_key = <<curve_id::8, _::8, private_key::binary>>
      )
      when is_binary(encoded_cipher) do
    key_size = key_size(curve_id)

    <<ephemeral_public_key::binary-size(key_size), tag::binary-16, cipher::binary>> =
      encoded_cipher

    # Derivate shared key using ECDH with the given ephermal public key and the private key
    shared_key =
      case ID.to_curve(curve_id) do
        :ed25519 ->
          x25519_sk = Ed25519.convert_to_x25519_private_key(private_key)
          :crypto.compute_key(:ecdh, ephemeral_public_key, x25519_sk, :x25519)

        curve ->
          :crypto.compute_key(:ecdh, ephemeral_public_key, private_key, curve)
      end

    # Generate keys for the AES authenticated decryption
    {iv, aes_key} = derivate_secrets(shared_key)

    case aes_auth_decrypt(iv, aes_key, cipher, tag) do
      :error ->
        {:error, :decryption_failed}

      data ->
        {:ok, data}
    end
  end

  @doc """
  Decrypt the cipher using first node private key
  """
  @spec ec_decrypt_with_first_node_key!(cipher :: binary()) :: term()
  def ec_decrypt_with_first_node_key!(cipher) do
    case ec_decrypt_with_first_node_key(cipher) do
      {:ok, data} ->
        data

      _ ->
        raise "Decrypted failed"
    end
  end

  @doc """
  Decrypt the cipher using last node private key
  """
  @spec ec_decrypt_with_last_node_key!(cipher :: binary()) :: term()
  def ec_decrypt_with_last_node_key!(cipher) do
    case ec_decrypt_with_last_node_key(cipher) do
      {:ok, data} ->
        data

      _ ->
        raise "Decrypted failed"
    end
  end

  @doc """
  Decrypt the cipher using first node private key
  """
  @spec ec_decrypt_with_first_node_key(cipher :: binary()) ::
          {:ok, term()} | {:error, :decryption_failed}
  def ec_decrypt_with_first_node_key(encoded_cipher) when is_binary(encoded_cipher) do
    <<curve_id::8, _::8, _::binary>> = NodeKeystore.last_public_key()
    key_size = key_size(curve_id)

    <<ephemeral_public_key::binary-size(key_size), tag::binary-16, cipher::binary>> =
      encoded_cipher

    # Derivate shared key using ECDH with the given ephermal public key and the node's private key
    shared_key = NodeKeystore.diffie_hellman_with_first_key(ephemeral_public_key)

    # Generate keys for the AES authenticated decryption
    {iv, aes_key} = derivate_secrets(shared_key)

    case aes_auth_decrypt(iv, aes_key, cipher, tag) do
      :error ->
        {:error, :decryption_failed}

      data ->
        {:ok, data}
    end
  end

  @doc """
  Decrypt the cipher using last node private key
  """
  @spec ec_decrypt_with_last_node_key(cipher :: binary()) ::
          {:ok, term()} | {:error, :decryption_failed}
  def ec_decrypt_with_last_node_key(encoded_cipher) do
    <<curve_id::8, _::8, _::binary>> = NodeKeystore.last_public_key()
    key_size = key_size(curve_id)

    <<ephemeral_public_key::binary-size(key_size), tag::binary-16, cipher::binary>> =
      encoded_cipher

    # Derivate shared key using ECDH with the given ephermal public key and the node's private key
    shared_key = NodeKeystore.diffie_hellman_with_last_key(ephemeral_public_key)

    # Generate keys for the AES authenticated decryption
    {iv, aes_key} = derivate_secrets(shared_key)

    case aes_auth_decrypt(iv, aes_key, cipher, tag) do
      :error ->
        {:error, :decryption_failed}

      data ->
        {:ok, data}
    end
  end

  @doc """
  Encrypt a data using AES authenticated encryption.
  """
  @spec aes_encrypt(data :: iodata(), key :: iodata()) :: aes_cipher
  def aes_encrypt(data, _key = <<key::binary-32>>) when is_binary(data) do
    iv = :crypto.strong_rand_bytes(12)
    {cipher, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, data, "", true)
    <<iv::binary-size(12), tag::binary-size(16), cipher::binary>>
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
  @spec aes_decrypt(_encoded_cipher :: aes_cipher, key :: binary) ::
          {:ok, term()} | {:error, :decryption_failed}
  def aes_decrypt(
        _encoded_cipher = <<iv::binary-12, tag::binary-16, cipher::binary>>,
        <<key::binary-32>>
      ) do
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
        {:error, :decryption_failed}

      data ->
        {:ok, data}
    end
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
  @spec aes_decrypt!(encoded_cipher :: aes_cipher, key :: binary) :: term()
  def aes_decrypt!(encoded_cipher, key) when is_binary(encoded_cipher) and is_binary(key) do
    case aes_decrypt(encoded_cipher, key) do
      {:ok, data} ->
        data

      {:error, :decryption_failed} ->
        raise "Decryption failed"
    end
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
  def hash(data, algo \\ Application.get_env(:archethic, __MODULE__)[:default_hash])

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
  def valid_public_key?(<<0::8, _::8, _::binary-size(32)>>), do: true
  def valid_public_key?(<<1::8, _::8, _::binary-size(65)>>), do: true
  def valid_public_key?(<<2::8, _::8, _::binary-size(65)>>), do: true
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
  def load_transaction(%Transaction{
        address: address,
        type: :node_shared_secrets,
        data: %TransactionData{keys: [key = %Key{secret: secret}]},
        validation_stamp: %ValidationStamp{
          timestamp: timestamp
        }
      }) do
    nb_transactions = TransactionChain.size(address)
    SharedSecretsKeystore.set_node_shared_secrets_key_index(nb_transactions)

    Logger.info("Node shared key chain positioned at #{nb_transactions}",
      transaction_address: Base.encode16(address),
      transaction_type: :node_shared_secrets
    )

    if Key.authorized_public_key?(key, last_node_public_key()) do
      encrypted_secret_key = Key.get_encrypted_key(key, last_node_public_key())

      daily_nonce_date = SharedSecrets.next_application_date(timestamp)

      unwrap_secrets(secret, encrypted_secret_key, daily_nonce_date)
    else
      :ok
    end
  end

  def load_transaction(%Transaction{type: :node_rewards, address: address}) do
    nb_transactions = TransactionChain.size(address)
    SharedSecretsKeystore.set_network_pool_key_index(nb_transactions)

    Logger.info("Network pool chain positioned at#{nb_transactions}",
      transaction_address: Base.encode16(address),
      transaction_type: :node_rewards
    )
  end

  def load_transaction(%Transaction{type: :node, address: address}) do
    if NodeKeystore.next_public_key() |> hash() == address do
      Logger.debug("Node next keypair loaded",
        transaction_address: Base.encode16(address),
        transaction_type: :node
      )

      NodeKeystore.persist_next_keypair()
    else
      :ok
    end
  end

  def load_transaction(_), do: :ok

  @doc """
  Return the storage nonce filepath
  """
  @spec storage_nonce_filepath() :: binary()
  def storage_nonce_filepath do
    rel_filepath =
      Application.get_env(:archethic, __MODULE__) |> Keyword.fetch!(:storage_nonce_file)

    Utils.mut_dir(rel_filepath)
  end

  @doc """
  Determine the origin of the key from an ID
  """
  @spec key_origin(non_neg_integer()) :: supported_origin()
  defdelegate key_origin(origin), to: ID, as: :to_origin

  @spec get_key_certificate(key()) :: binary()
  def get_key_certificate(<<_::8, origin_id::8, key::binary>>) do
    origin_id
    |> ID.to_origin()
    |> do_get_key_certificate(key)
  end

  defp do_get_key_certificate(:software, _) do
    ""
  end

  defp do_get_key_certificate(:tpm, key) do
    key_digest = :crypto.hash(:sha256, key) |> Base.encode16(case: :lower)

    cert_path =
      [
        Application.get_env(:archethic, __MODULE__) |> Keyword.fetch!(:key_certificates_dir),
        "#{key_digest}.bin"
      ]
      |> Path.join()
      |> Path.expand()

    case File.read(cert_path) do
      {:ok, data} ->
        data

      _ ->
        ""
    end
  end

  @doc """
  Return the Root CA public key for the given versioned public key 
  """
  @spec get_root_ca_public_key(key()) :: binary()
  def get_root_ca_public_key(<<_::8, origin_id::8, _::binary>>) do
    origin = ID.to_origin(origin_id)

    case Keyword.get(@certification_public_keys, origin) do
      nil ->
        ""

      "" ->
        ""

      <<_::binary-size(26), public_key::binary>> ->
        public_key
    end
  end

  @doc """
  Determine if the public key if authorized from the given certificate

  ## Examples

      iex> Crypto.verify_key_certificate?(
      ...> <<0, 0, 241, 101, 225, 229, 247, 194, 144, 229, 47, 46, 222, 243, 251, 171, 96,
      ...>  203, 174, 116, 191, 211, 39, 79, 142, 94, 225, 222, 51, 69, 201, 84, 161, 102>>,
      ...> <<48, 68, 2, 32, 90, 47, 10, 125, 165, 179, 88, 67, 83, 56, 55, 240, 78, 168,
      ...>  241, 104, 124, 212, 13, 10, 30, 80, 2, 170, 174, 8, 129, 205, 30, 40, 7, 196,
      ...>  2, 32, 27, 21, 21, 174, 186, 126, 63, 184, 50, 195, 46, 118, 188, 2, 112, 214,
      ...>  196, 121, 250, 48, 223, 110, 152, 189, 231, 137, 152, 25, 78, 29, 76, 191>>,
      ...> <<4, 210, 136, 107, 189, 140, 118, 86, 124, 217, 244, 69, 111, 61, 56, 224, 56, 150, 230,
      ...>  194, 203, 81, 213, 212, 220, 19, 1, 180, 114, 44, 230, 149, 21, 125, 69, 206, 32, 173,
      ...>  186, 81, 243, 58, 13, 198, 129, 169, 33, 179, 201, 50, 49, 67, 38, 156, 38, 199, 97, 59,
      ...>  70, 95, 28, 35, 233, 21, 230>>)
      true
  """
  @spec verify_key_certificate?(key(), binary(), binary()) :: boolean()
  def verify_key_certificate?(_, _, ""), do: true

  def verify_key_certificate?(<<_::8, origin_id::8, key::binary>>, certificate, root_ca_key)
      when is_binary(certificate) and is_binary(root_ca_key) do
    case ID.to_origin(origin_id) do
      :tpm ->
        ECDSA.verify?(:secp256r1, root_ca_key, key, certificate)

      :software ->
        true
    end
  end

  @doc """
  Get the public key elliptic curve
  """
  @spec get_public_key_curve(key()) :: supported_curve()
  def get_public_key_curve(<<curve_id::8, _::binary>>) do
    ID.to_curve(curve_id)
  end

  @doc """
  Get the default elliptic curve
  """
  @spec default_curve() :: supported_curve()
  def default_curve, do: Application.get_env(:archethic, __MODULE__)[:default_curve]
end
