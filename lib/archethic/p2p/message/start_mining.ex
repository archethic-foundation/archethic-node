defmodule Archethic.P2P.Message.StartMining do
  @moduledoc """
  Represents message to start the transaction mining.

  This message is initiated by the welcome node after the validation nodes election
  """
  @enforce_keys [:transaction, :welcome_node_public_key, :validation_node_public_keys]
  defstruct [:transaction, :welcome_node_public_key, :validation_node_public_keys]

  alias Archethic.Crypto
  alias Archethic.Mining
  alias Archethic.TransactionChain.Transaction
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error

  require Logger

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          welcome_node_public_key: Crypto.key(),
          validation_node_public_keys: list(Crypto.key())
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{
        transaction: tx,
        welcome_node_public_key: welcome_node_public_key,
        validation_node_public_keys: validation_node_public_keys
      }) do
    <<7::8, Transaction.serialize(tx)::binary, welcome_node_public_key::binary,
      length(validation_node_public_keys)::8,
      :erlang.list_to_binary(validation_node_public_keys)::binary>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | Error.t()
  def process(
        %__MODULE__{
          transaction: tx = %Transaction{},
          welcome_node_public_key: welcome_node_public_key,
          validation_node_public_keys: validation_nodes
        },
        _
      ) do
    with {:election, true} <- {:election, Mining.valid_election?(tx, validation_nodes)},
         {:elected, true} <-
           {:elected, Enum.any?(validation_nodes, &(&1 == Crypto.last_node_public_key()))},
         {:mining, false} <- {:mining, Mining.processing?(tx.address)} do
      {:ok, _} = Mining.start(tx, welcome_node_public_key, validation_nodes)
      %Ok{}
    else
      {:election, false} ->
        Logger.error("Invalid validation node election",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        %Error{reason: :network_issue}

      {:elected, false} ->
        Logger.error("Unexpected start mining message",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        %Error{reason: :network_issue}

      {:mining, true} ->
        Logger.warning("Transaction already in mining process",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        %Ok{}
    end
  end
end
