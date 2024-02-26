defmodule Archethic.TransactionChain.DBLedger.FileImpl do
  @moduledoc false

  alias Archethic.DB
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.Utils

  @behaviour Archethic.TransactionChain.DBLedger

  defdelegate child_spec(opts), to: __MODULE__.Supervisor

  @doc """
  Create the database folder
  """
  @spec setup_folder!() :: :ok
  def setup_folder!() do
    File.mkdir_p!(base_path())
  end

  @spec stream_inputs(address :: binary()) :: Enumerable.t() | list(VersionedTransactionInput.t())
  def stream_inputs(address) do
    address
    |> filename()
    |> File.open([:binary, :read])
    |> do_stream()
  end

  defp do_stream({:ok, fd}) do
    Stream.resource(
      fn -> fd end,
      fn fd ->
        with {:ok, <<size::32>>} <- :file.read(fd, 4),
             {:ok, binary} <- :file.read(fd, size) do
          {input, _} = VersionedTransactionInput.deserialize(binary)

          {[input], fd}
        else
          :eof -> {:halt, fd}
        end
      end,
      fn fd -> :file.close(fd) end
    )
  end

  defp do_stream({:error, _}), do: []

  @spec write_inputs(binary(), list(VersionedTransactionInput.t())) :: :ok
  def write_inputs(_address, []), do: :ok

  def write_inputs(address, inputs) do
    inputs_serialized =
      inputs
      |> Enum.map(fn input ->
        bin =
          input
          |> VersionedTransactionInput.serialize()
          |> Utils.wrap_binary()

        <<byte_size(bin)::32, bin::binary>>
      end)
      |> :erlang.list_to_binary()

    address
    |> filename()
    |> File.write!(inputs_serialized, [:binary, :write])
  end

  defp filename(address), do: Path.join([base_path(), Base.encode16(address)])
  defp base_path(), do: Path.join([DB.filepath(), "inputs"])
end
