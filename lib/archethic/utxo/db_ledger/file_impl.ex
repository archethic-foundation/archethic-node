defmodule Archethic.UTXO.DBLedger.FileImpl do
  @moduledoc false

  alias Archethic.DB

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput
  alias Archethic.Utils

  @behaviour Archethic.UTXO.DBLedger

  defdelegate child_spec(opts), to: __MODULE__.Supervisor

  @doc """
  Create the database folder
  """
  @spec setup_folder!() :: :ok
  def setup_folder!() do
    File.mkdir_p!(base_path())
  end

  defp base_path(), do: Path.join([DB.filepath(), "utxo"])

  def file_path(genesis_address) do
    Path.join(base_path(), Base.encode16(genesis_address))
  end

  @doc """
  Add unspent output for a genesis address
  """
  @spec append(binary(), VersionedUnspentOutput.t()) :: :ok
  def append(genesis_address, utxo = %VersionedUnspentOutput{}) do
    bin =
      utxo
      |> VersionedUnspentOutput.serialize()
      |> Utils.wrap_binary()

    File.write!(file_path(genesis_address), <<byte_size(bin)::32, bin::binary>>, [
      :append,
      :binary
    ])
  end

  @doc """
  Flush to disk the unspent outputs for a genesis address
  """
  @spec flush(binary(), list(VersionedUnspentOutput.t())) :: :ok
  def flush(genesis_address, unspent_outputs) do
    bin =
      unspent_outputs
      |> Enum.map(fn utxo ->
        bin =
          utxo
          |> VersionedUnspentOutput.serialize()
          |> Utils.wrap_binary()

        <<byte_size(bin)::32, bin::binary>>
      end)
      |> :erlang.list_to_binary()

    File.write!(file_path(genesis_address), bin, [
      :binary
    ])
  end

  @doc """
  Retrieve the serialized UTXO's state from the genesis address
  """
  @spec stream(binary()) :: list(VersionedUnspentOutput.t()) | Enumerable.t()
  def stream(genesis_address) do
    genesis_address
    |> file_path()
    |> File.open([:binary, :read])
    |> do_stream()
  end

  defp do_stream({:ok, fd}) do
    Stream.resource(
      fn -> fd end,
      fn fd ->
        with {:ok, <<size::32>>} <- :file.read(fd, 4),
             {:ok, binary} <- :file.read(fd, size) do
          {utxo, _} = VersionedUnspentOutput.deserialize(binary)

          {[utxo], fd}
        else
          :eof -> {:halt, fd}
        end
      end,
      fn fd -> :file.close(fd) end
    )
  end

  defp do_stream({:error, _}), do: []

  def list_genesis_addresses do
    case File.ls(base_path()) do
      {:ok, files} ->
        Enum.map(files, &Base.decode16/1)
      _ ->
        []
    end
  end
end
