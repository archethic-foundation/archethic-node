defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput do
  @moduledoc """
  Represent an unspent transaction output linked to a protocol version
  """

  defstruct [:protocol_version, :unspent_output]

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

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

  ## Examples

    iex> utxo = %UnspentOutput(from: random_address(), type: :UCO, amount: 100_000_000)
    iex> protocol_version = 1
    iex> VersionedUnspentOutput.wrap_unspent_output(utxo, protocol_version)
    %VersionedUnspentOutput{protocol_version: 1, unspent_output: utxo}
  """
  @spec wrap_unspent_output(utxo :: UnspentOutput.t(), protocol_version :: non_neg_integer()) ::
          t()
  def wrap_unspent_output(utxo, protocol_version),
    do: %__MODULE__{protocol_version: protocol_version, unspent_output: utxo}

  @doc """
  Unwrap a VersionedUnspentOuput into an UnspentOutput

  ## Examples

    iex> utxo = %UnspentOutput(from: random_address(), type: :UCO, amount: 100_000_000)
    iex> v_utxo = %VersionedUnspentOutput{protocol_version: 1, unspent_output: utxo}
    iex> VersionedUnspentOutput.unwrap_unspent_output(v_utxo)
    utxo
  """
  @spec unwrap_unspent_output(versioned_utxo :: t()) :: UnspentOutput.t()
  def unwrap_unspent_output(%__MODULE__{unspent_output: utxo}), do: utxo

  @doc """
  Wrap a list of UnspentOuput into a list of VersionedUnspentOutput

  ## Examples

    iex> utxo1 = %UnspentOutput(from: random_address(), type: :UCO, amount: 100_000_000)
    iex> utxo2 = %UnspentOutput(from: random_address(), type: :UCO, amount: 200_000_000)
    iex> protocol_version = 1
    iex> VersionedUnspentOutput.wrap_unspent_outputs([utxo1, utxo2], protocol_version)
    [
      %VersionedUnspentOutput{protocol_version: 1, unspent_output: utxo1},
      %VersionedUnspentOutput{protocol_version: 1, unspent_output: utxo2}
    ]
  """
  @spec wrap_unspent_outputs(
          utxos :: list(UnspentOutput.t()),
          protocol_version :: non_neg_integer()
        ) :: list(t())
  def wrap_unspent_outputs(utxos, protocol_version) when is_list(utxos),
    do: Enum.map(utxos, &wrap_unspent_output(&1, protocol_version))

  @doc """
  Unwrap a list of VersionedUnspentOuput into a list of UnspentOutput

  ## Examples

    iex> utxo1 = %UnspentOutput(from: random_address(), type: :UCO, amount: 100_000_000)
    iex> utxo2 = %UnspentOutput(from: random_address(), type: :UCO, amount: 200_000_000)
    iex> v_utxo1 = %VersionedUnspentOutput{protocol_version: 1, unspent_output: utxo1}
    iex> v_utxo2 = %VersionedUnspentOutput{protocol_version: 1, unspent_output: utxo2}
    iex> VersionedUnspentOutput.unwrap_unspent_outputs([v_utxo1, v_utxo2])
    [utxo1, utxo2]
  """
  @spec unwrap_unspent_outputs(versioned_utxos :: list(t())) :: list(UnspentOutput.t())
  def unwrap_unspent_outputs(utxos) when is_list(utxos),
    do: Enum.map(utxos, &unwrap_unspent_output/1)
end
