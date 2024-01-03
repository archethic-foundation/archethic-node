defmodule Archethic.Account.GenesisState do
  @moduledoc false

  alias Archethic.DB

  alias Archethic.Utils
  alias Archethic.Utils.VarInt
  alias Archethic.TransactionChain.VersionedTransactionInput

  @doc """
  Flush to disk the UTXO's state for a genesis address
  """
  @spec persist(binary(), list(VersionedTransactionInput.t())) :: :ok
  def persist(genesis_address, utxos) do
    bin =
      utxos
      |> Enum.map(&VersionedTransactionInput.serialize/1)
      |> :erlang.list_to_bitstring()
      |> Utils.wrap_binary()

    size_bin = VarInt.from_value(length(utxos))

    genesis_address
    |> file_path()
    |> File.write(<<size_bin::binary, bin::binary>>)
  end

  @doc """
  Returns the base path of all pending logs
  """
  @spec base_path() :: binary()
  def base_path(), do: Path.join([DB.filepath(), "genesis", "state"])

  @doc """
  Determines the state filename for a given address
  """
  @spec file_path(binary()) :: binary()
  def file_path(genesis_address) do
    Path.join(base_path(), Base.encode16(genesis_address))
  end

  @doc """
  Retrieve the serialized UTXO's state from the genesis address
  """
  @spec fetch(binary()) :: list(VersionedTransactionInput.t())
  def fetch(genesis_address) do
    case File.read(file_path(genesis_address)) do
      {:ok, bin} ->
        {nb_inputs, rest} = VarInt.get_value(bin)
        deserialize_inputs_file(rest, nb_inputs)

      {:error, _} ->
        []
    end
  end

  defp deserialize_inputs_file(bitstring, nb_inputs, acc \\ [])

  defp deserialize_inputs_file(_bitstring, nb_inputs, acc) when length(acc) == nb_inputs do
    Enum.reverse(acc)
  end

  defp deserialize_inputs_file(<<>>, _nb_inputs, _acc), do: []

  defp deserialize_inputs_file(bitstring, nb_inputs, acc) do
    {input, rest} = VersionedTransactionInput.deserialize(bitstring)
    deserialize_inputs_file(rest, nb_inputs, [input | acc])
  end
end
