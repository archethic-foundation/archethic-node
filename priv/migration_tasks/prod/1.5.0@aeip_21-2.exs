defmodule Migration_1_5_0 do
  @moduledoc """
  Merge transaction inputs into a single file
  """

  alias Archethic.DB

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.Utils

  def run() do
    [DB.filepath(), "inputs", "{uco,token,call}/*"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.group_by(fn path ->
      Regex.run(~r/inputs\/(uco|token|call)\/(.*)/, path) |> List.last()
    end)
    |> Task.async_stream(
      fn {address, filepaths} ->
        inputs =
          filepaths
          |> Enum.flat_map(fn path ->
            path
            |> File.read!()
            |> deserialize_inputs_file([])
          end)
          |> Enum.sort_by(& &1.input.timestamp, {:asc, DateTime})

        TransactionChain.write_inputs(Base.decode16!(address), inputs)
      end,
      timeout: :infinity
    )
    |> Stream.run()
  end

  defp deserialize_inputs_file(<<>>, acc), do: acc

  defp deserialize_inputs_file(bitstring, acc) do
    {input_bit_size, rest} = Utils.VarInt.get_value(bitstring)
    <<input_bitstring::bitstring-size(input_bit_size), rest::bitstring>> = rest

    {input, _padding} = VersionedTransactionInput.deserialize(input_bitstring)
    deserialize_inputs_file(rest, [input | acc])
  end
end
