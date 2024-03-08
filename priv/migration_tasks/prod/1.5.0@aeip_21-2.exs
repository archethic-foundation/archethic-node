defmodule Migration_1_5_0 do
  @moduledoc """
  Merge transaction inputs into a single file
  """

  alias Archethic.DB
  alias Archethic.Election
  alias Archethic.P2P

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
        next_address = fetch_next_address(address)

        inputs =
          filepaths
          |> Enum.flat_map(fn path ->
            path
            |> File.read!()
            |> deserialize_inputs_file([])
          end)
          |> Enum.sort_by(& &1.input.timestamp, {:asc, DateTime})

        TransactionChain.write_inputs(Base.decode16!(next_address), inputs)
      end,
      timeout: :infinity
    )
    |> Stream.run()
  end

  defp fetch_next_address(address) do
    authorized_nodes = P2P.authorized_and_available_nodes()
    storage_nodes = Election.storage_nodes(address, authorized_nodes)
    genesis_address = fetch_genesis_address(address, storage_nodes)

    if genesis_address == address do
      case TransactionChain.fetch_first_transaction_address(address, storage_nodes) do
        {:ok, first_address} ->
          first_address
        {:error, reason} ->
          raise "Migration_1_5_0 failed to fetch first transaction address for #{Base.encode16(address)} with #{reason}"
      end
    else
      case TransactionChain.fetch_next_chain_addresses(address, storage_nodes, limit: 1) do
        {:ok, [{next_address, _}]} ->
          next_address

        {:error, reason} ->
          raise "Migration_1_5_0 failed to fetch next address for #{Base.encode16(address)} with #{reason}"
      end
    end
  end

  defp fetch_genesis_address(address, storage_nodes) do
    case TransactionChain.fetch_genesis_address(address, storage_nodes) do
      {:ok, genesis_address} ->
        genesis_address
      {:error, reason} ->
        raise "Migration_1_5_0 failed to fetch genesis address for #{Base.encode16(address)} with #{reason}"
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
