defmodule Archethic.TransactionChain.TransactionData.Contract do
  @moduledoc """
  Represents a smart contract defnition

  - bytecode: the byte code of the compilied wasm code
  - manifest: the description of the contract functions
  """
  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils.TypedEncoding

  @enforce_keys [:bytecode, :manifest]
  defstruct [:bytecode, :manifest]

  @type t :: %__MODULE__{
          bytecode: binary(),
          manifest: map()
        }

  @doc """
  Serialize a contract
  """
  @spec serialize(
          recipient :: t(),
          version :: pos_integer(),
          serialization_mode :: Transaction.serialization_mode()
        ) :: bitstring()
  def serialize(recipient, version, serialization_mode \\ :compact)

  def serialize(%__MODULE__{bytecode: bytecode, manifest: manifest}, _version, serialization_mode) do
    <<byte_size(bytecode)::32, bytecode::binary,
      TypedEncoding.serialize(manifest, serialization_mode)::bitstring>>
  end

  @doc """
  Deserialize a contract
  """
  @spec deserialize(
          rest :: bitstring(),
          version :: pos_integer(),
          serialization_mode :: Transaction.serialization_mode()
        ) :: {t(), bitstring()}
  def deserialize(binary, version, serialization_mode \\ :compact)

  def deserialize(
        <<bytecode_size::32, bytecode::binary-size(bytecode_size), rest::bitstring>>,
        _,
        serialization_mode
      ) do
    {manifest, rest} = TypedEncoding.deserialize(rest, serialization_mode)

    {%__MODULE__{bytecode: bytecode, manifest: manifest}, rest}
  end

  @doc false
  @spec cast(contract :: nil | map()) :: nil | t()
  def cast(nil), do: nil

  def cast(%{bytecode: bytecode, manifest: manifest}),
    do: %__MODULE__{bytecode: bytecode, manifest: manifest}

  @doc false
  @spec to_map(contract :: nil | t()) :: nil | map()
  def to_map(nil), do: nil

  def to_map(%__MODULE__{bytecode: bytecode, manifest: manifest}) do
    %{"functions" => functions, "state" => state} = Map.get(manifest, "abi")

    upgrade_opts =
      case Map.get(manifest, "upgradeOpts") do
        %{"from" => from} -> %{from: from}
        nil -> nil
      end

    %{
      bytecode: Base.encode16(bytecode),
      manifest: %{
        abi: %{functions: functions, state: state},
        upgrade_opts: upgrade_opts
      }
    }
  end
end
