defmodule Archethic.DB.EmbeddedImpl.InputsReader do
  @moduledoc """
  Inputs are stored by destination address. 1 file per address per ledger
  """

  alias Archethic.DB.EmbeddedImpl.InputsWriter
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.Utils

  @spec get_inputs(ledger :: InputsWriter.ledger(), address :: binary()) ::
          list(VersionedTransactionInput.t())
  def get_inputs(ledger, address) do
    filename = InputsWriter.address_to_filename(ledger, address)

    case File.open(filename, [:read, :binary]) do
      {:error, :enoent} ->
        []

      {:ok, fd} ->
        case IO.binread(fd, :eof) do
          :eof ->
            []

          bin ->
            bin
            |> deserialize_inputs_file([])
            |> Enum.reverse()
        end
    end
  end

  defp deserialize_inputs_file(<<>>, acc), do: acc

  defp deserialize_inputs_file(bitstring, acc) do
    {input_bit_size, rest} = Utils.VarInt.get_value(bitstring)

    # every serialization contains some padding to be a binary (multipe of 8bits)
    {input_bitstring, rest} =
      case rem(input_bit_size, 8) do
        0 ->
          <<input_bitstring::bitstring-size(input_bit_size), rest::bitstring>> = rest
          {input_bitstring, rest}

        remainder ->
          <<input_bitstring::bitstring-size(input_bit_size),
            _padding::bitstring-size(8 - remainder), rest::bitstring>> = rest

          {input_bitstring, rest}
      end

    {input, <<>>} = VersionedTransactionInput.deserialize(input_bitstring)
    deserialize_inputs_file(rest, [input | acc])
  end
end
