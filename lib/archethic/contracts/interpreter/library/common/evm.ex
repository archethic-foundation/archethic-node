defmodule Archethic.Contracts.Interpreter.Library.Common.Evm do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Tag
  alias Archethic.Contracts.Interpreter.Legacy.UtilsInterpreter
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  use Tag

  @spec abi_encode(String.t(), list()) :: String.t()
  def abi_encode(signature, params \\ [])

  def abi_encode(signature, params) do
    # If signature is tuple "(address, uint)" we need to wrap params in tuple
    params = Enum.map(params, &decode_hex/1)

    params = if String.starts_with?(signature, "("), do: [List.to_tuple(params)], else: params

    ABI.encode(signature, params) |> Base.encode16(case: :lower)
  end

  @spec abi_decode(String.t(), String.t()) :: list()
  def abi_decode(signature, encoded_result) do
    encoded_result =
      if String.starts_with?(encoded_result, "0x"),
        do: String.slice(encoded_result, 2..-1),
        else: encoded_result

    encoded_result = Base.decode16!(encoded_result, case: :mixed)
    res = ABI.decode(signature, encoded_result)

    res =
      if String.starts_with?(signature, "("),
        do: res |> List.first() |> Tuple.to_list(),
        else: res

    encode_hex(res)
  end

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:abi_encode, [first]) do
    binary_or_variable_or_function?(first)
  end

  def check_types(:abi_encode, [first, second]) do
    check_types(:abi_encode, [first]) && list_or_variable_or_function?(second)
  end

  def check_types(:abi_decode, [first, second]) do
    binary_or_variable_or_function?(first) && binary_or_variable_or_function?(second)
  end

  def check_types(_, _), do: false

  defp binary_or_variable_or_function?(arg) do
    AST.is_binary?(arg) || AST.is_variable_or_function_call?(arg)
  end

  defp list_or_variable_or_function?(arg) do
    AST.is_list?(arg) || AST.is_variable_or_function_call?(arg)
  end

  defp decode_hex(value) when is_binary(value) do
    value = if String.starts_with?(value, "0x"), do: String.slice(value, 2..-1), else: value
    UtilsInterpreter.maybe_decode_hex(value)
  end

  defp decode_hex(value) when is_list(value), do: Enum.map(value, &decode_hex/1)
  defp decode_hex(value), do: value

  defp encode_hex(value) when is_binary(value) do
    if String.printable?(value), do: value, else: "0x" <> Base.encode16(value, case: :lower)
  end

  defp encode_hex(value) when is_list(value), do: Enum.map(value, &encode_hex/1)
  defp encode_hex(value), do: value
end
