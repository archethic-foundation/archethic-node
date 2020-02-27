defmodule UnirisCrypto do
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

  A local keystore is implemented through software or hardware according to the configuration choice
  and each time a generation keypair function is called, it's possible to store it as new node keypair.

  Some keys are preloaded by the system such as shared and origin keys.

  Node keys are labelled in the keystore can  be retrieved from the latest, the first or the previous generated key

  Shared keys are labelled in the keystore and can be retrieved from the latest and the first

  Origin keys in the keystore can be retrieve randomly
  """

  alias UnirisCrypto.ID
  alias UnirisCrypto.SoftwareImpl

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
  - 32 bytes for the IV (Initialization Vector)
  - 16 bytes for the Authentication tag
  - The rest for the ciphertext
  """
  @type aes_cipher :: <<_::384, _::_*8>>

  @typedoc """
  Options for the generation keypair:
  - curve: which elliptic curve to use
  - persistence: determines if the private key must be stored

  """
  @type key_generation_options :: [
          curve: supported_curve(),
          persistence: boolean()
        ]

  @type key_access :: [
          with: :node | :origin | :shared,
          as: :first | :last | :previous | :random
        ]

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

  Options can specifies:
  - curve: which curve to use during the generation
  - persistence: determines if the key must be stored

  Returns the public key generated

  """
  @spec derivate_keypair(index :: non_neg_integer(), options :: key_generation_options()) ::
          public_key :: key()
  def derivate_keypair(
        index \\ 1,
        options \\ [curve: Application.get_env(:uniris_crypto, :default_curve)]
      )
      when is_integer(index) and index >= 0 and is_list(options) do
    if Keyword.has_key?(options, :curve) do
      impl().derivate_keypair(index, options)
    else
      impl().derivate_keypair(
        index,
        options ++ [curve: Application.get_env(:uniris_crypto, :default_curve)]
      )
    end
  end

  @doc """
  Generate a new random keypair using the seed from the local keystore and a given supported elliptic curve

  Options can specifies:
  - curve: which curve to use during the generation
  - persistence: determines if the key must be stored

  Returns the public key generated
  """
  @spec generate_random_keypair(options :: key_generation_options()) :: public_key :: key()
  def generate_random_keypair(
        options \\ [curve: Application.get_env(:uniris_crypto, :default_curve)]
      )
      when is_list(options) do
    if Keyword.has_key?(options, :curve) do
      impl().generate_random_keypair(options)
    else
      impl().generate_random_keypair(
        options ++ [curve: Application.get_env(:uniris_crypto, :default_curve)]
      )
    end
  end

  @doc """
  Generate a keypair in a deterministic way using a seed

  Options can specifies:
  - curve: which curve to use during the generation
  - persistence: determines if the key must be stored

  Returns the public key generated


  ## Examples

      iex> UnirisCrypto.generate_deterministic_keypair("myseed", [curve: :ed25519])
      <<0, 195, 217, 87, 74, 44, 143, 133, 202, 49, 24, 21, 172, 125, 120, 229, 214,
      229, 203, 0, 171, 137, 3, 53, 26, 206, 212, 108, 55, 78, 175, 52, 104>>

      iex> UnirisCrypto.generate_deterministic_keypair("myseed", [curve: :secp256r1])
      <<1, 4, 71, 234, 56, 77, 247, 36, 202, 205, 0, 115, 85, 40, 74, 90, 107, 180,
      162, 184, 168, 248, 179, 160, 69, 68, 159, 128, 0, 23, 81, 29, 122, 89, 51,
      182, 115, 31, 213, 158, 244, 116, 92, 197, 246, 196, 55, 27, 8, 205, 62, 39,
      55, 227, 59, 94, 246, 213, 26, 22, 150, 137, 167, 23, 69, 144>>

  """
  @spec generate_deterministic_keypair(seed :: binary(), options :: key_generation_options()) ::
          public_key :: key()
  def generate_deterministic_keypair(
        seed,
        options \\ [curve: Application.get_env(:uniris_crypto, :default_curve)]
      )
      when is_binary(seed) and is_list(options) do
    if Keyword.has_key?(options, :curve) do
      impl().generate_deterministic_keypair(seed, options)
    else
      impl().generate_deterministic_keypair(
        seed,
        options ++ [curve: Application.get_env(:uniris_crypto, :default_curve)]
      )
    end
  end

  @doc """
  Check the validity of a public key.

  The first byte of the public key identifies the curve and the validation rules to apply.

  ## Examples

      iex> pub = Crypto.generate_random_keypair([curve: :ed25519])
      iex> UnirisCrypto.valid_public_key?(pub)
      true

      iex> pub = Crypto.generate_random_keypair([curve: :secp256r1])
      iex> UnirisCrypto.valid_public_key?(pub)
      true

  Invalid size of public key return an error:

      iex> UnirisCrypto.valid_public_key?(<<1,0>>)
      false
  """
  @spec valid_public_key?(key()) :: boolean()
  def valid_public_key?(<<curve_id::8, key::binary>>) do
    curve = ID.curve_from_id(curve_id)
    do_valid_public_key?(curve, key)
  end

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
  Sign data.

  The first byte of the private key identifies the curve and the signature algorithm to use

  ## Examples

      iex> UnirisCrypto.generate_deterministic_keypair("myseed", [persistence: true])
      iex> UnirisCrypto.sign("myfakedata", [with: :node, as: :last])
      <<240, 207, 59, 29, 236, 164, 157, 87, 84, 62, 177, 26, 76, 69, 209, 125, 110,
      136, 168, 113, 112, 243, 155, 254, 59, 214, 193, 191, 112, 55, 194, 220, 2,
      190, 0, 1, 214, 104, 252, 133, 3, 112, 19, 27, 129, 231, 237, 59, 174, 4, 82,
      210, 110, 204, 219, 237, 197, 26, 140, 63, 97, 67, 27, 8>>
  """
  @spec sign(binary() | term(), key_access :: key_access()) :: signature :: binary()
  def sign(data, key_access) when is_binary(data) do
    impl().sign(data, key_access)
  end

  def sign(data, key_access), do: sign(:erlang.term_to_binary(data), key_access)

  @doc """
  Verify a signature.

  The first byte of the public key identifies the curve and the verification algorithl to use.

  ## Examples

      iex> pub = UnirisCrypto.generate_deterministic_keypair("myseed", [persistence: true])
      iex> sig = UnirisCrypto.sign("myfakedata", [with: :node, as: :last])
      iex> UnirisCrypto.verify(sig, "myfakedata", pub)
      true

  Returns an error when the signature is invalid
      iex> pub = UnirisCrypto.generate_deterministic_keypair("myseed")
      iex> sig = <<1, 48, 69, 2, 33, 0, 185, 231, 7, 86, 207, 253, 8, 230, 199, 94, 251, 33, 42, 172, 95, 93, 7, 209, 175, 69, 216, 121, 239, 24, 17, 21, 41, 129, 255, 49, 153, 116, 2, 32, 85, 1, 212, 69, 182, 98, 174, 213, 79, 154, 69, 84, 149, 126, 169, 44, 98, 64, 21, 211, 20, 235, 165, 97, 61, 8, 239, 194, 196, 177, 46, 199>>
      iex> UnirisCrypto.verify(sig, "myfakedata", pub)
      false
  """
  @spec verify(signature :: binary(), data :: term() | binary(), public_key :: key()) :: boolean()
  def verify(
        sig,
        data,
        <<curve_id::8, key::binary>> = _public_key
      )
      when is_binary(data) do
    curve = ID.curve_from_id(curve_id)
    SoftwareImpl.verify(curve, key, data, sig)
  end

  def verify(sig, data, key),
    do: verify(sig, :erlang.term_to_binary(data), key)

  @doc """
  Encrypts data using public key authenticated encryption (ECIES).

  Ephemeral and random ECDH key pair is generated which is used to generate shared
  secret with the given public key(transformed to ECDH public key).

  Based on this secret, KDF derivate keys are used to create an authenticated symmetric encryption.

  ## Examples

      ```
      pub = UnirisCrypto.generate_random_keypair()
      UnirisCrypto.ec_encrypt("myfakedata", pub)
      <<0, 0, 0, 0, 58, 138, 57, 196, 76, 95, 222, 131, 128, 248, 50, 146, 221, 145,
      152, 20, 45, 164, 221, 166, 242, 172, 237, 36, 238, 150, 238, 127, 53, 160,
      43, 159, 91, 6, 234, 99, 42, 174, 193, 165, 203, 74, 99, 179, 225, 137, 159,
      30, 79, 81, 24, 47, 27, 175, 252, 252, 64, 11, 207>>
      ```
  """
  @spec ec_encrypt(message :: term() | binary(), public_key :: key()) :: binary()
  def ec_encrypt(message, <<curve_id::8, key::binary>> = _public_key) when is_binary(message) do
    curve = ID.curve_from_id(curve_id)
    impl().ec_encrypt(curve, key, message)
  end

  def ec_encrypt(message, public_key),
    do: ec_encrypt(:erlang.term_to_binary(message), public_key)

  @doc """
  Decrypt a cipher using public key authenticated encryption (ECIES).

  A cipher contains a generated ephemeral random public key coupled with an authentication tag.

  Private key is transformed to ECDH to compute a shared secret with this random public key.

  Based on this secret, KDF derivate keys are used to create an authenticated symmetric decryption.

  Before the decryption, the authentication will be checked to ensure the given private key
  has the right to decrypt this data.

  ## Examples

      iex> cipher = <<0, 0, 0, 58, 16, 25, 106, 181, 34, 80, 25, 136, 170, 141, 8, 112, 178, 140, 1, 180, 192, 35, 141, 241, 149, 179, 111, 154, 57, 244, 88, 102, 57, 95, 240, 17, 121, 194, 181, 224, 45, 68, 115, 111, 19, 136, 156, 91, 231, 53, 171, 79, 231, 226, 122, 76, 38, 129, 81, 79, 43, 133>>
      iex> UnirisCrypto.generate_deterministic_keypair("myseed", [persistence: true])
      iex> UnirisCrypto.ec_decrypt!(cipher, [with: :node, as: :last])
      "myfakedata"

  Invalid message to decrypt or key return an error:

      iex> UnirisCrypto.generate_random_keypair(persistence: true)
      iex> UnirisCrypto.ec_decrypt!(<<0, 0, 0>>, [with: :node, as: :last])
      ** (RuntimeError) Decryption failed
  """
  @spec ec_decrypt!(cipher :: binary(), key_access :: key_access) :: term()
  def ec_decrypt!(cipher, key_access) when is_binary(cipher) and is_list(key_access) do
    case impl().ec_decrypt!(cipher, key_access) do
      <<131::8, _>> = data ->
        :erlang.binary_to_term(data, [:safe])

      data ->
        data
    end
  end

  @doc """
  Encrypt a data using AES authenticated encryption.
  """
  @spec aes_encrypt(data :: term(), key :: binary) :: aes_cipher

  @spec aes_encrypt(data :: binary(), key :: binary) :: aes_cipher
  def aes_encrypt(data, <<key::binary-32>>) when is_binary(data),
    do: impl().aes_encrypt(data, key)

  def aes_encrypt(data, key),
    do: aes_encrypt(:erlang.term_to_binary(data), key)

  @doc """
  Decrypt a ciphertext using the AES authenticated decryption.

  ## Examples

      iex> key = <<234, 210, 202, 129, 91, 76, 68, 14, 17, 212, 197, 49, 66, 168, 52, 111, 176,
      ...> 182, 227, 156, 5, 32, 24, 105, 41, 152, 67, 191, 187, 209, 101, 36>>
      iex> ciphertext = UnirisCrypto.aes_encrypt("sensitive data", key)
      iex> UnirisCrypto.aes_decrypt!(ciphertext, key)
      "sensitive data"

  Return an error when the key is invalid

      iex> ciphertext = UnirisCrypto.aes_encrypt("sensitive data", :crypto.strong_rand_bytes(32))
      iex> UnirisCrypto.aes_decrypt!(ciphertext, :crypto.strong_rand_bytes(32))
      ** (RuntimeError) Decryption failed

  """
  @spec aes_decrypt!(cipher :: aes_cipher, key :: binary) :: term()
  def aes_decrypt!(<<_iv::32*8, _tag::8*16, _::binary>> = cipher, <<key::binary-32>>) do
    case impl().aes_decrypt!(cipher, key) do
      <<131::8, _>> = data ->
        :erlang.binary_to_term(data, [:safe])

      data ->
        data
    end
  end


  @doc """
  Hash a data.

  A first-byte prepends each hash to indicate the algorithm used.

  ## Examples

      iex> UnirisCrypto.hash("myfakedata", :sha256)
      <<0, 78, 137, 232, 16, 150, 235, 9, 199, 74, 41, 189, 246, 110, 65, 252, 17,
      139, 109, 23, 172, 84, 114, 35, 202, 102, 41, 167, 23, 36, 230, 159, 35>>

      iex> UnirisCrypto.hash("myfakedata", :blake2b)
      <<4, 244, 16, 24, 144, 16, 67, 113, 164, 214, 115, 237, 113, 126, 130, 76, 128,
      99, 78, 223, 60, 179, 158, 62, 239, 245, 85, 4, 156, 10, 2, 94, 95, 19, 166,
      170, 147, 140, 117, 1, 169, 132, 113, 202, 217, 193, 56, 112, 193, 62, 134,
      145, 233, 114, 41, 228, 164, 180, 225, 147, 2, 33, 192, 42, 184>>

      iex> UnirisCrypto.hash("myfakedata", :sha3_256)
      <<2, 157, 219, 54, 234, 186, 251, 4, 122, 216, 105, 185, 228, 211, 94, 44, 94,
      104, 147, 182, 189, 45, 28, 219, 218, 236, 19, 66, 87, 121, 240, 249, 218>>
  """
  @spec hash(data :: map() | binary(), algo :: supported_hash()) ::
          hash() | {:error, :invalid_hash_algo}
  def hash(data, algo \\ Application.get_env(:uniris_crypto, :default_hash))

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

  @doc """
  Checks if a hash is valid

  ## Examples

      iex> hash = UnirisCrypto.hash("mydata", :sha256)
      iex> UnirisCrypto.valid_hash?(hash)
      true

      iex> UnirisCrypto.valid_hash?("myfakesha256")
      false

      iex> UnirisCrypto.valid_hash?(:crypto.strong_rand_bytes(32))
      false
  """
  @spec valid_hash?(hash()) :: boolean()
  def valid_hash?(<<0::8, hash::binary>>), do: byte_size(hash) == 32
  def valid_hash?(<<1::8, hash::binary>>), do: byte_size(hash) == 64
  def valid_hash?(<<2::8, hash::binary>>), do: byte_size(hash) == 32
  def valid_hash?(<<3::8, hash::binary>>), do: byte_size(hash) == 64
  def valid_hash?(<<4::8, hash::binary>>), do: byte_size(hash) == 64
  def valid_hash?(_hash), do: false

  @doc """
  Get the first public key from the node keystore
  """
  def first_node_public_key() do
    impl().first_node_public_key()
  end

  @doc """
  Get the last public key from the node keystore
  """
  def last_node_public_key() do
    impl().last_node_public_key()
  end

  @doc """
  Get the previous public key from the node keystore
  """
  def previous_node_public_key() do
     impl().previous_node_public_key()
  end

  @doc """
  Get the first public key from the shared keystore
  """
  def first_shared_public_key() do
    impl().first_shared_public_key()
  end

  @doc """
  Get the last public key from the shared keystore
  """
  def last_shared_public_key() do
    impl().last_shared_public_key()
  end

  @doc """
  Generate node shared keys from a given seed and number of transactions through derivation

  The first shared key will also be generated

  Those keys will be stored inside the keystore
  """
  @spec generate_shared_keys(binary(), pos_integer()) :: :ok
  def generate_shared_keys(seed, last_index)
      when last_index >= 0 do
    impl().generate_shared_keys(seed, last_index)
  end

  @doc """
  Load a set of origin keypairs into the keystore
  """
  @spec load_origin_keys(list({binary, binary})) :: :ok
  def load_origin_keys(origin_keys) do
    impl().load_origin_keys(origin_keys)
  end

  defp impl, do: Application.get_env(:uniris_crypto, :impl, UnirisCrypto.SoftwareImpl)
end
