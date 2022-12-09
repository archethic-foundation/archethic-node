defmodule Archethic.DB.EmbeddedImpl.InputsReader do
  @moduledoc """
  Inputs are stored by destination address. 1 file per address per ledger
  """

  alias Archethic.DB.EmbeddedImpl.InputsWriter
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.Utils

  # sobelow_skip ["Traversal.FileModule"]
  @spec get_inputs(input_type :: InputsWriter.input_type(), address :: binary()) ::
          list(VersionedTransactionInput.t())
  def get_inputs(ledger, address) do
    filename = InputsWriter.address_to_filename(ledger, address)

    case File.read(filename) do
      {:error, :enoent} ->
        []

      {:ok, bin} ->
        bin
        |> deserialize_inputs_file([])
    end
  end

  defp deserialize_inputs_file(<<>>, acc), do: acc

  defp deserialize_inputs_file(bitstring, acc) do
    {input_bit_size, rest} = Utils.VarInt.get_value(bitstring)
    <<input_bitstring::bitstring-size(input_bit_size), rest::bitstring>> = rest

    {input, _padding} = VersionedTransactionInput.deserialize(input_bitstring)
    deserialize_inputs_file(rest, [input | acc])
  end
end
