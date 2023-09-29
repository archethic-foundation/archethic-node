defmodule Archethic.Account.GenesisPendingLog do
  @moduledoc """
  This module is in charge to maintain the genesis pending log of inputs.

  Each time a transaction target another transaction chain, the pending log will be filled with new inputs, as unspent output transaction.
  This log is persisted to provide fault tolerance in case of mem table crash.

  This log is cleared when the targetted transaction chain makes a new transaction and then serialize its pending state into a aggregated one.
  """

  alias Archethic.Utils
  alias Archethic.TransactionChain.VersionedTransactionInput

  @doc """
  Add input to the pending log file
  """
  @spec append(binary(), VersionedTransactionInput.t()) :: :ok
  def append(genesis_address, input = %VersionedTransactionInput{}) do
    bin =
      input
      |> VersionedTransactionInput.serialize()
      |> Utils.wrap_binary()

    File.write!(file_path(genesis_address), <<byte_size(bin)::32, bin::binary>>, [
      :append,
      :binary
    ])
  end

  @doc """
  Remove the pending log for the given address
  """
  @spec clear(binary()) :: :ok
  def clear(genesis_address) do
    genesis_address
    |> file_path()
    |> File.rm()
  end

  @doc """
  Stream the pending transaction inputs from the pending genesis address
  """
  @spec stream(binary()) :: Enumerable.t() | list(VersionedTransactionInput.t())
  def stream(genesis_address) do
    case File.open(file_path(genesis_address), [:binary, :read]) do
      {:ok, fd} ->
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

      {:error, _} ->
        []
    end
  end

  @doc """
  Determines the pending log filename for a given address
  """
  @spec file_path(binary()) :: binary()
  def file_path(genesis_address) do
    Path.join(base_path(), Base.encode16(genesis_address))
  end

  @doc """
  Returns the base path of all pending logs
  """
  @spec base_path() :: binary()
  def base_path() do
    Utils.mut_dir("genesis/pending")
  end
end
