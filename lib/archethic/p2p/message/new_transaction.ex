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

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{transaction: tx}) do
    <<6::8, Transaction.serialize(tx)::bitstring>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | Error.t()
  def process(%__MODULE__{transaction: tx}, sender_public_key) do
    case Archethic.send_new_transaction(tx, sender_public_key) do
      :ok ->
        %Ok{}

      {:error, :network_issue} ->
        %Error{reason: :network_issue}
    end
  end
end
