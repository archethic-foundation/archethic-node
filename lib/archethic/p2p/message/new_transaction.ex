defmodule Archethic.P2P.Message.NewTransaction do
  @moduledoc """
  Represents a message to request the process of a new transaction

  This message is used locally within a node during the bootstrap
  """
  @enforce_keys [:transaction, :welcome_node]
  defstruct [:transaction, :welcome_node, :contract_context]

  alias Archethic.Contracts.Contract
  alias Archethic.Crypto
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error
  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          welcome_node: Crypto.key(),
          contract_context: nil | Contract.Context.t()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: Ok.t() | Error.t()
  def process(
        %__MODULE__{
          transaction: tx,
          welcome_node: node_pbkey,
          contract_context: contract_context
        },
        _
      ) do
    Archethic.send_new_transaction(tx,
      welcome_node_key: node_pbkey,
      contract_context: contract_context,
      forward?: true
    )

    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        transaction: tx,
        welcome_node: node_pbkey,
        contract_context: contract_context
      }) do
    serialized_contract_context =
      case contract_context do
        nil ->
          <<0::8>>

        _ ->
          <<1::8, Contract.Context.serialize(contract_context)::bitstring>>
      end

    <<Transaction.serialize(tx)::bitstring, node_pbkey::binary,
      serialized_contract_context::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)
    {node_pbkey, rest} = Utils.deserialize_public_key(rest)

    {contract_context, rest} =
      case rest do
        <<0::8, rest::bitstring>> ->
          {nil, rest}

        <<1::8, rest::bitstring>> ->
          Contract.Context.deserialize(rest)
      end

    {%__MODULE__{
       transaction: tx,
       welcome_node: node_pbkey,
       contract_context: contract_context
     }, rest}
  end
end
