defmodule Archethic.P2P.Message.NewTransaction do
  @moduledoc """
  Represents a message to request the process of a new transaction

  This message is used locally within a node during the bootstrap
  """
  @enforce_keys [:transaction, :welcome_node]
  defstruct [:transaction, :welcome_node, :contract_context]

  alias Archethic.Contracts.Contract
  alias Archethic.Crypto
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error
  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          welcome_node: Crypto.key(),
          contract_context: nil | Contract.Context.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | Error.t()
  def process(
        %__MODULE__{
          transaction: tx,
          welcome_node: node_pbkey,
          contract_context: contract_context
        },
        _
      ) do
    :ok = Archethic.send_new_transaction(tx, node_pbkey, contract_context)
    %Ok{}
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
