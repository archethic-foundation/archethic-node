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
    :p2p_view_hash,
    :contract_context
  ]

  alias Archethic.Contracts.Contract
  alias Archethic.Crypto
  alias Archethic.Mining
  alias Archethic.Utils
  alias Archethic.TransactionChain.Transaction
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error
  alias Archethic.SelfRepair.NetworkChain
  alias Archethic.SelfRepair.NetworkView

  require Logger

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          welcome_node_public_key: Crypto.key(),
          validation_node_public_keys: list(Crypto.key()),
          network_chains_view_hash: binary(),
          p2p_view_hash: binary(),
          contract_context: nil | Contract.Context.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | Error.t()
  def process(
        %__MODULE__{
          transaction: tx = %Transaction{},
          welcome_node_public_key: welcome_node_public_key,
          validation_node_public_keys: validation_nodes,
          network_chains_view_hash: network_chains_view_hash,
          p2p_view_hash: p2p_view_hash,
          contract_context: contract_context
        },
        _
      ) do
    with :ok <- check_synchronization(network_chains_view_hash, p2p_view_hash),
         :ok <- check_valid_election(tx, validation_nodes),
         :ok <- check_current_node_is_elected(validation_nodes),
         :ok <- check_not_already_mining(tx.address) do
      {:ok, _} = Mining.start(tx, welcome_node_public_key, validation_nodes, contract_context)
      %Ok{}
    else
      {:error, :invalid_validation_nodes_election} ->
        Logger.error("Invalid validation node election",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        %Error{reason: :network_issue}

      {:error, :current_node_not_elected} ->
        Logger.error("Unexpected start mining message",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        %Error{reason: :network_issue}

      {:error, :transaction_already_mining} ->
        Logger.warning("Transaction already in mining process",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        %Ok{}

      {:error, {:sync_issue, sync_issue}} ->
        Logger.warning("Current node may be out of synchronization: #{inspect(sync_issue)}",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

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
      network_chains_view_hash::binary, p2p_view_hash::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)

    {welcome_node_public_key, <<nb_validation_nodes::8, rest::bitstring>>} =
      Utils.deserialize_public_key(rest)

    {validation_node_public_keys, rest} =
      Utils.deserialize_public_key_list(rest, nb_validation_nodes, [])

    <<network_chains_view_hash::binary-size(32), p2p_view_hash::binary-size(32), rest::bitstring>> =
      rest

    {%__MODULE__{
       transaction: tx,
       welcome_node_public_key: welcome_node_public_key,
       validation_node_public_keys: validation_node_public_keys,
       network_chains_view_hash: network_chains_view_hash,
       p2p_view_hash: p2p_view_hash
     }, rest}
  end

  defp check_not_already_mining(address) do
    if Mining.processing?(address) do
      {:error, :transaction_already_mining}
    else
      :ok
    end
  end

  defp check_current_node_is_elected(validation_nodes) do
    if Enum.any?(validation_nodes, &(&1 == Crypto.last_node_public_key())) do
      :ok
    else
      {:error, :current_node_not_elected}
    end
  end

  defp check_valid_election(tx, validation_nodes) do
    if Mining.valid_election?(tx, validation_nodes) do
      :ok
    else
      {:error, :invalid_validation_nodes_election}
    end
  end

  defp check_synchronization(network_chains_view_hash, p2p_view_hash) do
    case {network_chains_view_hash == NetworkView.get_chains_hash(),
          p2p_view_hash == NetworkView.get_p2p_hash()} do
      {true, true} ->
        :ok

      {false, false} ->
        NetworkChain.asynchronous_resync_many([
          :node,
          :oracle,
          :origin,
          :node_shared_secrets
        ])

        {:error, {:sync_issue, :both_sync}}

      {true, false} ->
        NetworkChain.asynchronous_resync(:node)
        {:error, {:sync_issue, :p2p_sync}}

      {false, true} ->
        NetworkChain.asynchronous_resync_many([
          :oracle,
          :origin,
          :node_shared_secrets
        ])

        {:error, {:sync_issue, :network_chains_sync}}
    end
  end
end
