defmodule ArchEthic.P2P.Message.NewTransaction do
  @moduledoc """
  Represents a message to request the process of a new transaction

  This message is used locally within a node during the bootstrap
  """
  defstruct [:transaction]

  alias ArchEthic
  alias ArchEthic.P2P.Message.Error
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.TransactionChain.Transaction

  use ArchEthic.P2P.Message, message_id: 6

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }

  def encode(%__MODULE__{transaction: tx}) do
    Transaction.serialize(tx)
  end

  def decode(message) when is_bitstring(message) do
    {tx, rest} = Transaction.deserialize(message)

    {
      %__MODULE__{
        transaction: tx
      },
      rest
    }
  end

  def process(%__MODULE__{transaction: tx}) do
    case ArchEthic.send_new_transaction(tx) do
      :ok ->
        %Ok{}

      {:error, :network_issue} ->
        %Error{reason: :network_issue}
    end
  end
end
