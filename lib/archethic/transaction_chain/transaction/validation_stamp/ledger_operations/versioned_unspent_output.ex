defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput do
  @moduledoc """
  Represent an unspent transaction output linked to a protocol version
  """

  defstruct [:protocol_version, :unspent_output]

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.Utils

  @type t :: %__MODULE__{
          protocol_version: pos_integer(),
          unspent_output: UnspentOutput.t()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(
        utxo = %__MODULE__{
          protocol_version: protocol_version,
          unspent_output: %UnspentOutput{type: :call}
        }
      )
      when protocol_version < 7,
      # Before AEIP-21 call where not serialized in unspent output so the serialization / deserialization
      # does not work with protocol version < 7
      do: serialize(%__MODULE__{utxo | protocol_version: 7})

  def serialize(%__MODULE__{
        protocol_version: protocol_version,
        unspent_output: unspent_output = %UnspentOutput{}
      }) do
    <<protocol_version::32, UnspentOutput.serialize(unspent_output, protocol_version)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<protocol_version::32, rest::bitstring>>) do
    {unspent_output, rest} = UnspentOutput.deserialize(rest, protocol_version)

    {
      %__MODULE__{
        protocol_version: protocol_version,
        unspent_output: unspent_output
      },
      rest
    }
  end

  @doc """
  Build %VersionedUnspentOutput struct from map
  """
  @spec cast(map()) :: __MODULE__.t()
  def cast(versioned_unspent_output = %{}) do
    %__MODULE__{
      protocol_version: Map.get(versioned_unspent_output, :protocol_version),
      unspent_output: versioned_unspent_output |> Map.get(:unspent_output) |> UnspentOutput.cast()
    }
  end

  @doc """
  Build %VersionedUnspentOutput struct from map
  """
  @spec to_map(versioned_unspent_output :: t()) :: map()
  def to_map(%__MODULE__{unspent_output: utxo, protocol_version: protocol_version}) do
    utxo |> UnspentOutput.to_map() |> Map.put(:protocol_version, protocol_version)
  end

  @doc """
  Wrap an UnspentOuput into a VersionedUnspentOutput
  """
  @spec wrap_unspent_output(utxo :: UnspentOutput.t(), protocol_version :: non_neg_integer()) ::
          t()
  def wrap_unspent_output(utxo, protocol_version),
    do: %__MODULE__{protocol_version: protocol_version, unspent_output: utxo}

  @doc """
  Unwrap a VersionedUnspentOuput into an UnspentOutput
  """
  @spec unwrap_unspent_output(versioned_utxo :: t()) :: UnspentOutput.t()
  def unwrap_unspent_output(%__MODULE__{unspent_output: utxo}), do: utxo

  @doc """
  Wrap a list of UnspentOuput into a list of VersionedUnspentOutput
  """
  @spec wrap_unspent_outputs(
          utxos :: list(UnspentOutput.t()),
          protocol_version :: non_neg_integer()
        ) :: list(t())
  def wrap_unspent_outputs(utxos, protocol_version),
    do: Enum.map(utxos, &wrap_unspent_output(&1, protocol_version))

  @doc """
  Unwrap a list of VersionedUnspentOuput into a list of UnspentOutput
  """
  @spec unwrap_unspent_outputs(versioned_utxos :: list(t())) :: list(UnspentOutput.t())
  def unwrap_unspent_outputs(utxos),
    do: Enum.map(utxos, &unwrap_unspent_output/1)

  @doc """
  Return a hash of the utxo
  Used for cheap comparaison
  """
  @spec hash(t()) :: binary()
  def hash(
        utxo = %__MODULE__{
          protocol_version: protocol_version,
          unspent_output: %UnspentOutput{type: :call}
        }
      )
      when protocol_version < 7,
      # Before AEIP-21 call where not serialized in unspent output so the serialization / deserialization
      # does not work with protocol version < 7
      do: hash(%__MODULE__{utxo | protocol_version: 7})

  def hash(%__MODULE__{protocol_version: protocol_version, unspent_output: utxo}) do
    utxo
    |> UnspentOutput.serialize(protocol_version)
    |> Utils.wrap_binary()
    |> then(&:crypto.hash(:sha256, &1))
  end

  @doc """
  Compare two VersionedUnspentOutput
  This function is usefull when using Enum.sort(utxos, {:asc, VersionedUnspentOutput})
  """
  @spec compare(versioned_utxo1 :: t(), versioned_utxo2 :: t()) :: :lt | :gt | :eq
  def compare(%__MODULE__{protocol_version: v1}, %__MODULE__{protocol_version: v2}) when v1 < v2,
    do: :lt

  def compare(%__MODULE__{protocol_version: v1}, %__MODULE__{protocol_version: v2}) when v1 > v2,
    do: :gt

  def compare(%__MODULE__{unspent_output: utxo1}, %__MODULE__{unspent_output: utxo2}),
    do: UnspentOutput.compare(utxo1, utxo2)
end
