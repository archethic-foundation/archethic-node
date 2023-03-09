defmodule Archethic.P2P.Message.StartMining do
  @moduledoc """
  Represents message to start the transaction mining.

  This message is initiated by the welcome node after the validation nodes election
  """
  @enforce_keys [
    :transaction,
    :welcome_node_public_key,
    :validation_node_public_keys,
    :network_chains_view_hash,
    :p2p_view_hash
  ]
  defstruct [
    :transaction,
    :welcome_node_public_key,
    :validation_node_public_keys,
    :network_chains_view_hash,
    :p2p_view_hash
  ]

  alias Archethic.Crypto
  alias Archethic.Mining
  alias Archethic.Utils
  alias Archethic.TransactionChain.Transaction
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error
  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.NetworkView

  require Logger

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          welcome_node_public_key: Crypto.key(),
          validation_node_public_keys: list(Crypto.key()),
          network_chains_view_hash: binary(),
          p2p_view_hash: binary()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | Error.t()
  def process(
        %__MODULE__{
          transaction: tx = %Transaction{},
          welcome_node_public_key: welcome_node_public_key,
          validation_node_public_keys: validation_nodes,
          network_chains_view_hash: network_chains_view_hash,
          p2p_view_hash: p2p_view_hash
        },
        _
      ) do
    case check_synchronization(network_chains_view_hash, p2p_view_hash) do
      :ok ->
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

      {:error, sync_issue} ->
        Logger.warning("Current node may be out of synchronization: #{inspect(sync_issue)}",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        case sync_issue do
          :network_chains_sync ->
            SelfRepair.resync_all_network_chains()

          :p2p_sync ->
            SelfRepair.resync_p2p()

          :both_sync ->
            SelfRepair.resync_all_network_chains()
            SelfRepair.resync_p2p()
        end

        %Error{reason: sync_issue}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        transaction: tx,
        welcome_node_public_key: welcome_node_public_key,
        validation_node_public_keys: validation_node_public_keys,
        network_chains_view_hash: network_chains_view_hash,
        p2p_view_hash: p2p_view_hash
      }) do
    <<Transaction.serialize(tx)::binary, welcome_node_public_key::binary,
      length(validation_node_public_keys)::8,
      :erlang.list_to_binary(validation_node_public_keys)::binary,
      byte_size(network_chains_view_hash)::8, network_chains_view_hash::binary,
      byte_size(p2p_view_hash)::8, p2p_view_hash::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)

    {welcome_node_public_key, <<nb_validation_nodes::8, rest::bitstring>>} =
      Utils.deserialize_public_key(rest)

    {validation_node_public_keys, rest} =
      Utils.deserialize_public_key_list(rest, nb_validation_nodes, [])

    <<
      network_chains_view_hash_bytes::8,
      network_chains_view_hash::binary-size(network_chains_view_hash_bytes),
      p2p_view_hash_bytes::8,
      p2p_view_hash::binary-size(p2p_view_hash_bytes),
      rest::bitstring
    >> = rest

    {%__MODULE__{
       transaction: tx,
       welcome_node_public_key: welcome_node_public_key,
       validation_node_public_keys: validation_node_public_keys,
       network_chains_view_hash: network_chains_view_hash,
       p2p_view_hash: p2p_view_hash
     }, rest}
  end

  defp check_synchronization(network_chains_view_hash, p2p_view_hash) do
    case {network_chains_view_hash == NetworkView.get_chains_hash(),
          p2p_view_hash == NetworkView.get_p2p_hash()} do
      {true, true} ->
        :ok

      {false, false} ->
        {:error, :both_sync}

      {true, false} ->
        {:error, :p2p_sync}

      {false, true} ->
        {:error, :network_chains_sync}
    end
  end
end
