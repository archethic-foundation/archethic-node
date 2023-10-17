defmodule Archethic.TransactionChain.TransactionData.Recipient.ArgumentsEncoding do
  @moduledoc """
  Handle encoding of recipients arguments
  """

  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils.TypedEncoding

  @spec serialize(args :: list(TypedEncoding.arg()), mode :: Transaction.serialization_mode()) ::
          bitstring()
  def serialize(args, mode) do
    bin =
      args
      |> Enum.map(&TypedEncoding.serialize(&1, mode))
      |> :erlang.list_to_bitstring()

    <<length(args)::8, bin::bitstring>>
  end

  @spec deserialize(binary :: bitstring(), mode :: Transaction.serialization_mode()) ::
          {list(TypedEncoding.arg()), bitstring()}
  def deserialize(<<nb_args::8, rest::bitstring>>, mode) do
    do_deserialize(rest, nb_args, [], mode)
  end

  defp do_deserialize(<<>>, _nb_args, acc, _mode), do: {Enum.reverse(acc), <<>>}

  defp do_deserialize(rest, nb_args, acc, _mode) when length(acc) == nb_args do
    {Enum.reverse(acc), rest}
  end

  defp do_deserialize(binary, nb_args, acc, mode) do
    {arg, rest} = TypedEncoding.deserialize(binary, mode)
    do_deserialize(rest, nb_args, [arg | acc], mode)
  end
end
