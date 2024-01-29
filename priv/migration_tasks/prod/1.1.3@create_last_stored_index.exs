defmodule Migration_1_1_3 do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.DB.EmbeddedImpl
  alias Archethic.DB.EmbeddedImpl.ChainIndex
  alias Archethic.DB.EmbeddedImpl.ChainReader
  alias Archethic.DB.EmbeddedImpl.ChainWriter

  alias Archethic.TransactionChain.Transaction

  def run() do
    db_path = EmbeddedImpl.filepath()

    get_genesis_addresses(db_path) |> index_last_addresses(db_path)
  end

  defp get_genesis_addresses(db_path) do
    if chain_index_started?() do
      ChainIndex.list_genesis_addresses()
    else
      get_genesis_addresses_from_index(db_path)
    end
  end

  defp chain_index_started?(), do: Process.whereis(ChainIndex) != nil

  defp get_genesis_addresses_from_index(db_path) do
    Task.async_stream(0..255, fn subset ->
      filename = index_summary_path(db_path, subset)

      case File.open(filename, [:binary, :read]) do
        {:ok, fd} ->
          do_get_genesis_addresses_from_index(fd, [])

        {:error, _} ->
          []
      end
    end)
    |> Stream.flat_map(fn {:ok, genesis_addresses} -> genesis_addresses end)
    |> Stream.uniq()
  end

  defp index_summary_path(db_path, subset) do
    Path.join([ChainWriter.base_chain_path(db_path), "#{Base.encode16(<<subset>>)}-summary"])
  end

  defp do_get_genesis_addresses_from_index(fd, acc) do
    with {:ok, <<_current_curve_id::8, current_hash_type::8>>} <- :file.read(fd, 2),
         hash_size <- Crypto.hash_size(current_hash_type),
         {:ok, _current_digest} <- :file.read(fd, hash_size),
         {:ok, <<genesis_curve_id::8, genesis_hash_type::8>>} <- :file.read(fd, 2),
         hash_size <- Crypto.hash_size(genesis_hash_type),
         {:ok, genesis_digest} <- :file.read(fd, hash_size),
         {:ok, <<_size::32, _offset::32>>} <- :file.read(fd, 8) do
      genesis_address = <<genesis_curve_id::8, genesis_hash_type::8, genesis_digest::binary>>

      do_get_genesis_addresses_from_index(fd, [genesis_address | acc])
    else
      :eof ->
        :file.close(fd)
        acc
    end
  end

  defp index_last_addresses(genesis_addresses, db_path) do
    Task.async_stream(genesis_addresses, &index_last_address(&1, db_path), timeout: :infinity)
    |> Stream.run()
  end

  defp index_last_address(genesis_address, db_path) do
    [%Transaction{address: address}] =
      ChainReader.stream_chain(genesis_address, [:address], db_path) |> Enum.take(-1)

    ChainIndex.set_last_chain_address_stored(genesis_address, address, db_path)
  end
end
