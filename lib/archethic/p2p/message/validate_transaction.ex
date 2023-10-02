defmodule Archethic.P2P.Message.ValidateTransaction do
  @moduledoc false

  @enforce_keys [:transaction]
  defstruct [:transaction, :contract_context]

  alias Archethic.Contracts.Contract
  alias Archethic.TransactionChain.Transaction
  alias Archethic.P2P.Message.ReplicationError
  alias Archethic.P2P.Message.Ok
  alias Archethic.Replication
  alias Archethic.Crypto

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          contract_context: nil | Contract.Context.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | ReplicationError.t()
  def process(%__MODULE__{transaction: tx, contract_context: contract_context}, _) do
    case Replication.validate_transaction(tx, contract_context) do
      :ok ->
        Replication.add_transaction_to_commit_pool(tx)
        %Ok{}

      {:error, reason} ->
        %ReplicationError{address: tx.address, reason: reason}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{transaction: tx, contract_context: nil}) do
    <<Transaction.serialize(tx)::bitstring, 0::8>>
  end

  def serialize(%__MODULE__{transaction: tx, contract_context: contract_context}) do
    <<Transaction.serialize(tx)::bitstring, 1::8,
      Contract.Context.serialize(contract_context)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(bin) when is_bitstring(bin) do
    {tx, rest} = Transaction.deserialize(bin)

    {contract_context, rest} =
      case rest do
        <<0::8, rest::bitstring>> -> {nil, rest}
        <<1::8, rest::bitstring>> -> Contract.Context.deserialize(rest)
      end

    {
      %__MODULE__{transaction: tx, contract_context: contract_context},
      rest
    }
  end
end
