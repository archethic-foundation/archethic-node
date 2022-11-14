defmodule Archethic.DB.EmbeddedImpl.Inputs do
  @moduledoc """
  Inputs are stored by destination address. 1 file per address
  There will be many files
  """

  alias Archethic.DB.EmbeddedImpl
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.Utils

  @spec append_inputs(inputs :: list(VersionedTransactionInput.t()), address :: binary()) :: :ok
  def append_inputs(inputs, address) do
    filename = address_to_filename(address)
    :ok = File.mkdir_p!(Path.dirname(filename))
    write_inputs_to_file(filename, inputs)
  end

  @spec get_inputs(address :: binary()) :: list(VersionedTransactionInput.t())
  def get_inputs(address) do
    address
    |> address_to_filename()
    |> read_inputs_from_file()
  end

  defp read_inputs_from_file(filename) do
    case File.read(filename) do
      {:ok, bin} ->
        Enum.reverse(deserialize_inputs_file(bin, []))

      _ ->
        []
    end
  end

  defp write_inputs_to_file(filename, inputs) do
    inputs_bin =
      inputs
      |> Enum.map(&VersionedTransactionInput.serialize(&1))
      |> :erlang.list_to_bitstring()
      |> Utils.wrap_binary()

    File.write!(filename, inputs_bin, [:append, :binary])
  end

  # instead of ignoring padding, we should count the iteration and stop once over
  defp deserialize_inputs_file(bin, acc) do
    if bit_size(bin) < 8 do
      # less than a byte, we are in the padding of wrap_binary
      acc
    else
      # todo: ORDER?
      # deserialize ONE input and return the rest
      {input, rest} = VersionedTransactionInput.deserialize(bin)
      deserialize_inputs_file(rest, [input | acc])
    end
  end

  defp address_to_filename(address),
    do: Path.join([EmbeddedImpl.db_path(), "inputs", Base.encode16(address)])
end
