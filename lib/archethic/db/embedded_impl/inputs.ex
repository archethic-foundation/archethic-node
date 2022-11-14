defmodule Archethic.DB.EmbeddedImpl.Inputs do
  @moduledoc """
  Inputs are stored by destination address. 1 file per address
  There will be many files
  """

  use GenServer

  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.Utils

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec append_inputs(inputs :: list(VersionedTransactionInput.t()), address :: binary()) :: :ok
  def append_inputs(inputs, address) do
    GenServer.call(__MODULE__, {:append_inputs, inputs, address})
  end

  @spec get_inputs(address :: binary()) :: list(VersionedTransactionInput.t())
  def get_inputs(address) do
    GenServer.call(__MODULE__, {:get_inputs, address})
  end

  def init(opts) do
    db_path = Keyword.get(opts, :path)
    input_path = Path.join(db_path, "inputs")

    # setup folder
    :ok = File.mkdir_p!(input_path)

    {:ok, %{input_path: input_path}}
  end

  def handle_call({:get_inputs, address}, _, state = %{input_path: input_path}) do
    inputs =
      address
      |> address_to_filename(input_path)
      |> read_inputs_from_file()

    {:reply, inputs, state}
  end

  def handle_call({:append_inputs, inputs, address}, _, state = %{input_path: input_path}) do
    address
    |> address_to_filename(input_path)
    |> write_inputs_to_file(inputs)

    {:reply, :ok, state}
  end

  defp read_inputs_from_file(filename) do
    case File.read(filename) do
      {:ok, bin} ->
        deserialize_inputs_file(bin, [])

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

  defp address_to_filename(address, path), do: Path.join([path, Base.encode16(address)])
end
