defmodule Archethic.DB.EmbeddedImpl.InputsWriter do
  @moduledoc """
  Inputs are stored by destination address. 1 file per address
  There will be many files
  """
  use GenServer

  alias Archethic.DB.EmbeddedImpl
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.Utils

  @type ledger :: :token | :UCO

  @spec start_link(ledger :: ledger, address :: binary()) :: {:ok, pid()}
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

  @spec address_to_filename(ledger :: ledger, address :: binary()) :: String.t()
  def address_to_filename(ledger, address) do
    prefix =
      case ledger do
        :UCO -> "uco"
        :token -> "token"
      end

    Path.join([EmbeddedImpl.db_path(), "inputs", prefix, Base.encode16(address)])
  end

  def init(opts) do
    ledger = Keyword.get(opts, :ledger)
    address = Keyword.get(opts, :address)
    filename = address_to_filename(ledger, address)
    :ok = File.mkdir_p!(Path.dirname(filename))

    {:ok, %{filename: filename, fd: File.open!(filename, [:read, :append, :binary])}}
  end

  def terminate(_reason, %{fd: fd}) do
    File.close(fd)
  end

  def handle_call({:append_input, input}, _from, state = %{fd: fd}) do
    # we need to pad the bitstring to be a binary
    # we also need to prefix with the number of bits to be able to ignore padding to deserialize
    serialized_input = VersionedTransactionInput.serialize(input)
    encoded_size = Utils.VarInt.from_value(bit_size(serialized_input))
    wrapped_bin = Utils.wrap_binary(<<encoded_size::binary, serialized_input::bitstring>>)

    IO.binwrite(fd, wrapped_bin)
    {:reply, :ok, state}
  end
end
