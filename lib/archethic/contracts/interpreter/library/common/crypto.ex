defmodule Archethic.Contracts.Interpreter.Library.Common.Crypto do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Legacy
  alias Archethic.Contracts.Interpreter.Legacy.UtilsInterpreter
  alias Archethic.Contracts.Interpreter.Scope

  alias Archethic.Crypto

  alias Archethic.Tag

  use Tag

  @spec hash(binary(), binary()) :: binary()
  def hash(content, algo \\ "sha256")

  def hash(content, "keccak256"),
    do: UtilsInterpreter.maybe_decode_hex(content) |> ExKeccak.hash_256() |> Base.encode16()

  def hash(content, algo), do: Legacy.Library.hash(content, algo)

  @spec sign_with_recovery(hash :: binary()) :: map()
  def sign_with_recovery(hash) do
    hash_payload =
      case Base.decode16(hash) do
        {:ok, hash_payload} ->
          hash_payload

        :error ->
          raise Library.Error,
            message: "Crypto.sign_with_recovery had an invalid hash in parameter"
      end

    seed = get_contract_seed("Crypto.sign")

    {_pub, <<_::16, priv::binary>>} = Crypto.derive_keypair(seed, 0, :secp256k1)

    {:ok, {r, s, v}} = ExSecp256k1.sign(hash_payload, priv)

    %{
      "r" => Base.encode16(r),
      "s" => Base.encode16(s),
      "v" => v
    }
  end

  @spec hmac(data :: binary(), algo :: binary(), key :: binary()) :: binary()
  def hmac(data, algo \\ "sha256", key \\ "")

  def hmac(data, algo, key) do
    key =
      if key == "" do
        payload = Crypto.storage_nonce() <> get_contract_seed("Crypto.hmac")
        :crypto.hash(:sha256, payload)
      else
        UtilsInterpreter.maybe_decode_hex(key)
      end

    algo =
      case algo do
        "sha256" ->
          :sha256

        "sha512" ->
          :sha512

        "sha3_256" ->
          :sha3_256

        "sha3_512" ->
          :sha3_512

        algo ->
          raise Library.Error, message: "Invalid hmac algorithm #{inspect(algo)}"
      end

    data = UtilsInterpreter.maybe_decode_hex(data)

    :crypto.mac(:hmac, algo, key, data) |> Base.encode16()
  end

  defp get_contract_seed(function) do
    case Scope.read_global([:encrypted_seed]) do
      nil ->
        raise Library.Error, message: "Contract seed has not been set for #{function}"

      {encrypted_seed, encrypted_key} ->
        with {:ok, aes_key} <- Crypto.ec_decrypt_with_storage_nonce(encrypted_key),
             {:ok, seed} <- Crypto.aes_decrypt(encrypted_seed, aes_key) do
          seed
        else
          _ -> raise Library.Error, message: "Unable to decrypt seed for #{function}"
        end
    end
  end

  @spec decrypt_with_storage_nonce(binary()) :: binary()
  def decrypt_with_storage_nonce(cipher) do
    case cipher
         |> UtilsInterpreter.maybe_decode_hex()
         |> Crypto.ec_decrypt_with_storage_nonce() do
      {:ok, data} ->
        data

      {:error, :decryption_failed} ->
        raise Library.Error, message: "Unable to decrypt data with storage nonce"
    end
  end

  @doc """
  This function uses the process dictionnary to have a fixed entropy.
  This is required because the ec_encrypt would not be determinist without it.

  Caller is supposed to pass the hash(contract_tx.private_key)
  """
  @spec encrypt(data :: binary(), public_key :: binary()) :: binary()
  def encrypt(data, public_key) do
    data = UtilsInterpreter.maybe_decode_hex(data)
    public_key = UtilsInterpreter.maybe_decode_hex(public_key)

    Archethic.Crypto.ec_encrypt(
      data,
      public_key,
      :crypto.hash(:sha256, Process.get(:ephemeral_entropy_priv_key))
    )
  end

  @spec encrypt_with_storage_nonce(data :: binary()) :: binary()
  def encrypt_with_storage_nonce(data) do
    data
    |> UtilsInterpreter.maybe_decode_hex()
    |> Crypto.ec_encrypt_with_storage_nonce()
  end

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:hash, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:hash, [first, second]) do
    check_types(:hash, [first]) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:sign_with_recovery, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:hmac, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:hmac, [first, second]) do
    check_types(:hmac, [first]) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:hmac, [first, second, third]) do
    check_types(:hmac, [first, second]) &&
      (AST.is_binary?(third) || AST.is_variable_or_function_call?(third))
  end

  def check_types(:decrypt_with_storage_nonce, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:encrypt, [first, second]) do
    (AST.is_binary?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:encrypt_with_storage_nonce, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
