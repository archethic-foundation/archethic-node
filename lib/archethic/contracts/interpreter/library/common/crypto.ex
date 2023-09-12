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

    case Scope.read_global([:encrypted_seed]) do
      nil ->
        raise Library.Error, message: "Contract seed has not been set for Crypto.sign"

      {encrypted_seed, encrypted_key} ->
        seed = get_seed(encrypted_seed, encrypted_key)

        {_pub, <<_::16, priv::binary>>} = Crypto.derive_keypair(seed, 0, :secp256k1)

        {:ok, {r, s, v}} = ExSecp256k1.sign(hash_payload, priv)

        %{
          "r" => Base.encode16(r),
          "s" => Base.encode16(s),
          "v" => v
        }
    end
  end

  defp get_seed(encrypted_seed, encrypted_key) do
    with {:ok, aes_key} <- Crypto.ec_decrypt_with_storage_nonce(encrypted_key),
         {:ok, seed} <- Crypto.aes_decrypt(encrypted_seed, aes_key) do
      seed
    else
      _ -> raise Library.Error, message: "Unable to decrypt seed in Crypto.sign"
    end
  end

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:hash, [first, second]) do
    (AST.is_binary?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:hash, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:sign_with_recovery, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
