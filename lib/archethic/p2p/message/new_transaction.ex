defmodule Archethic.P2P.Message.NewTransaction do
  @moduledoc """
  Represents a message to request the process of a new transaction

  This message is used locally within a node during the bootstrap
  """
  @enforce_keys [:transaction, :welcome_node]
  defstruct [:transaction, :welcome_node]

  alias Archethic.{TransactionChain.Transaction, Crypto, Utils, P2P.Message}
  alias Message.{Ok, Error}

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          welcome_node: Crypto.key()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | Error.t()
  def process(%__MODULE__{transaction: tx, welcome_node: node_pbkey}, _) do
    case Archethic.send_new_transaction(tx, node_pbkey) do
      :ok ->
        %Ok{}

      {:error, :network_issue} ->
        %Error{reason: :network_issue}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{transaction: tx, welcome_node: node_pbkey}) do
    <<Transaction.serialize(tx)::bitstring, node_pbkey::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)
    {node_pbkey, rest} = Utils.deserialize_public_key(rest)
    {%__MODULE__{transaction: tx, welcome_node: node_pbkey}, rest}
  end
end
