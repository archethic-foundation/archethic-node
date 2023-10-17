defmodule Archethic.TransactionChain.TransactionData.Recipient.ArgumentsEncoding do
  @moduledoc """
  Handle encoding of recipients arguments
  """

  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils.TypedEncoding

  @spec serialize(args :: list(TypedEncoding.arg()), mode :: Transaction.serialization_mode()) ::
          bitstring()
  def serialize(args, mode) when is_list(args) and mode in [:compact, :extended] do
    bit_size =
      case mode do
        :compact ->
          1

        :extended ->
          8
      end

    bin =
      args
      |> Enum.map(&TypedEncoding.serialize(&1, bit_size))
      |> :erlang.list_to_bitstring()

    <<length(args)::8, bin::bitstring>>
  end

  @spec deserialize(binary :: bitstring(), mode :: Transaction.serialization_mode()) ::
          {list(TypedEncoding.arg()), bitstring()}
  def deserialize(<<nb_args::8, rest::bitstring>>, mode) when mode in [:compact, :extended] do
    bit_size =
      case mode do
        :compact ->
          1

        :extended ->
          8
      end

    do_deserialize(rest, nb_args, [], bit_size)
  end

  defp do_deserialize(<<>>, _nb_args, acc, _bit_size), do: {Enum.reverse(acc), <<>>}

  defp do_deserialize(rest, nb_args, acc, _bit_size) when length(acc) == nb_args do
    {Enum.reverse(acc), rest}
  end

  defp do_deserialize(binary, nb_args, acc, bit_size) do
    {arg, rest} = TypedEncoding.deserialize(binary, bit_size)
    do_deserialize(rest, nb_args, [arg | acc], bit_size)
  end
end
