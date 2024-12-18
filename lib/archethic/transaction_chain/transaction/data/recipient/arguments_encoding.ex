defmodule Archethic.TransactionChain.TransactionData.Recipient.ArgumentsEncoding do
  @moduledoc """
  Handle encoding of recipients arguments
  """

  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils.TypedEncoding

  @spec serialize(
          args :: list(TypedEncoding.arg() | map()),
          mode :: Transaction.serialization_mode(),
          version :: pos_integer()
        ) ::
          bitstring()
  def serialize(args, mode, _version = 3) when is_list(args) do
    bin =
      args
      |> Enum.map(&TypedEncoding.serialize(&1, mode))
      |> :erlang.list_to_bitstring()

    <<length(args)::8, bin::bitstring>>
  end

  def serialize(args, mode, _version) when is_map(args) do
    <<1::8, TypedEncoding.serialize(args, mode)::bitstring>>
  end

  @spec deserialize(
          binary :: bitstring(),
          mode :: Transaction.serialization_mode(),
          version :: pos_integer()
        ) ::
          {list(TypedEncoding.arg()) | map(), bitstring()}
  def deserialize(<<nb_args::8, rest::bitstring>>, mode, version) do
    {args, rest} = do_deserialize(rest, nb_args, [], mode)

    if version <= 3 do
      {args, rest}
    else
      {Enum.at(args, 0), rest}
    end
  end

  defp do_deserialize(<<>>, _nb_args, acc, _mode), do: {Enum.reverse(acc), <<>>}

  defp do_deserialize(rest, nb_args, acc, _mode)
       when length(acc) > 0 and length(acc) == nb_args do
    {Enum.reverse(acc), rest}
  end

  defp do_deserialize(binary, nb_args, acc, mode) do
    {arg, rest} = TypedEncoding.deserialize(binary, mode)
    do_deserialize(rest, nb_args, [arg | acc], mode)
  end
end
