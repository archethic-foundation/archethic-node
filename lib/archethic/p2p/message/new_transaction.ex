defmodule Archethic.P2P.Message.NewTransaction do
  @moduledoc """
  Represents a message to request the process of a new transaction

  This message is used locally within a node during the bootstrap
  """
  defstruct [:transaction]

  alias Archethic.TransactionChain.Transaction
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error
  alias Archethic.Crypto

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | Error.t()
  def process(%__MODULE__{transaction: tx}, sender_public_key) do
    case Archethic.send_new_transaction(tx, sender_public_key) do
      :ok ->
        %Ok{}

      {:error, :network_issue} ->
        %Error{reason: :network_issue}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{transaction: tx}) do
    <<Transaction.serialize(tx)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)
    {%__MODULE__{transaction: tx}, rest}
  end
end
