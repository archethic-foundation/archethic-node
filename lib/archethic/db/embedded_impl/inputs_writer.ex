defmodule Archethic.DB.EmbeddedImpl.InputsWriter do
  @moduledoc """
  Inputs are stored by destination address. 1 file per address per ledger
  There will be many files
  """
  use GenServer
  @vsn 1

  alias Archethic.DB.EmbeddedImpl
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.Utils

  @type input_type :: :UCO | :token | :call

  @spec start_link(type :: input_type(), address :: binary()) ::
          {:ok, pid()}
  def start_link(ledger, address) do
    GenServer.start_link(__MODULE__, ledger: ledger, address: address)
  end

  @spec stop(pid :: pid()) :: :ok
  def stop(pid) do
    GenServer.stop(pid)
  end

  @spec append_input(
          pid :: pid(),
          input :: VersionedTransactionInput.t()
        ) :: :ok
  def append_input(pid, input) do
    GenServer.call(pid, {:append_input, input})
  end

  @spec address_to_filename(type :: input_type(), address :: binary()) ::
          String.t()
  def address_to_filename(ledger, address) do
    prefix =
      case ledger do
        :UCO -> "uco"
        :token -> "token"
        :call -> "call"
      end

    Path.join([EmbeddedImpl.db_path(), "inputs", prefix, Base.encode16(address)])
  end

  def init(opts) do
    ledger = Keyword.get(opts, :ledger)
    address = Keyword.get(opts, :address)
    filename = address_to_filename(ledger, address)
    :ok = File.mkdir_p!(Path.dirname(filename))

    # We use the `exclusive` flag. This means we can only open a file that does not exist yet.
    # We use this mechanism to prevent rewriting the same data over and over when we restart the node and reprocess the transaction history.
    # If the InputsWriter is called on an existing file, it will behave as normal but will write to the null device (= do nothing)
    # This optimization is possible only because we always spend all the inputs of an address at the same time
    fd =
      case File.open(filename, [:binary, :exclusive]) do
        {:error, :eexist} ->
          File.open!("/dev/null", [:binary, :write])

        {:ok, iodevice} ->
          iodevice
      end

    {:ok, %{filename: filename, fd: fd}}
  end

  def terminate(_reason, %{fd: fd}) do
    File.close(fd)
  end

  def handle_call({:append_input, input}, _from, state = %{fd: fd}) do
    # we need to pad the bitstring to be a binary
    # we also need to prefix with the number of bits to be able to ignore padding to deserialize
    serialized_input = Utils.wrap_binary(VersionedTransactionInput.serialize(input))
    encoded_size = Utils.VarInt.from_value(bit_size(serialized_input))
    IO.binwrite(fd, <<encoded_size::binary, serialized_input::binary>>)
    {:reply, :ok, state}
  end
end
