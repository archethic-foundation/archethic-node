defmodule Archethic.P2P.Message.StartMining do
  @moduledoc """
  Represents message to start the transaction mining.

  This message is initiated by the welcome node after the validation nodes election
  """
  @enforce_keys [
    :transaction,
    :welcome_node_public_key,
    :synchronization_node_public_keys,
    :network_chains_view_hash,
    :p2p_view_hash,
    :ref_timestamp
  ]
  defstruct [
    :transaction,
    :welcome_node_public_key,
    :synchronization_node_public_keys,
    :network_chains_view_hash,
    :p2p_view_hash,
    :contract_context,
    :ref_timestamp
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

  @ref_timestamp_drift :archethic
                       |> Application.compile_env!([Archethic.Mining, :start_mining_message_drift])

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          welcome_node_public_key: Crypto.key(),
          synchronization_node_public_keys: list(Crypto.key()),
          network_chains_view_hash: binary(),
          p2p_view_hash: binary(),
          contract_context: nil | Contract.Context.t(),
          ref_timestamp: DateTime.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | Error.t()
  def process(
        %__MODULE__{
          transaction: tx = %Transaction{},
          welcome_node_public_key: welcome_node_public_key,
          synchronization_node_public_keys: synchronization_nodes,
          network_chains_view_hash: network_chains_view_hash,
          p2p_view_hash: p2p_view_hash,
          contract_context: contract_context,
          ref_timestamp: ref_timestamp
        },
        _
      ) do
    validation_nodes = Mining.get_validation_nodes(tx, ref_timestamp)

    with :ok <- check_ref_timestamp(ref_timestamp),
         :ok <- check_synchronization(network_chains_view_hash, p2p_view_hash),
         :ok <- check_valid_synchronization_nodes(synchronization_nodes, validation_nodes),
         :ok <- check_current_node_is_elected(synchronization_nodes),
         :ok <- check_not_already_mining(tx.address),
         :ok <- Mining.request_chain_lock(tx) do
      {:ok, _} =
        Mining.start(
          tx,
          welcome_node_public_key,
          synchronization_nodes,
          contract_context,
          ref_timestamp
        )

      %Ok{}
    else
      {:error, reason} -> get_response(tx, reason)
    end
  end

  defp get_response(tx, :invalid_synchronization_nodes_election) do
    Logger.error("Invalid synchronization node election",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    %Error{reason: :network_issue}
  end

  defp get_response(tx, :current_node_not_elected) do
    Logger.error("Unexpected start mining message",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    %Error{reason: :network_issue}
  end

  defp get_response(tx, :transaction_already_mining) do
    Logger.warning("Transaction already in mining process",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    %Ok{}
  end

  defp get_response(tx, {:sync_issue, sync_issue}) do
    Logger.warning("Current node may be out of synchronization: #{inspect(sync_issue)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    %Error{reason: sync_issue}
  end

  defp get_response(tx, :already_locked) do
    Logger.warning("Transaction address is already locked with different data",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    %Error{reason: :already_locked}
  end

  defp get_response(tx, :invalid_ref_timestamp) do
    Logger.warning("StartMining message was received after ref timestamp drift",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    %Error{reason: :network_issue}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        transaction: tx,
        welcome_node_public_key: welcome_node_public_key,
        synchronization_node_public_keys: synchronization_node_public_keys,
        network_chains_view_hash: network_chains_view_hash,
        p2p_view_hash: p2p_view_hash,
        contract_context: contract_context,
        ref_timestamp: ref_timestamp
      }) do
    serialized_contract_context =
      case contract_context do
        nil -> <<0::8>>
        _ -> <<1::8, Contract.Context.serialize(contract_context)::bitstring>>
      end

    <<Transaction.serialize(tx)::bitstring, welcome_node_public_key::binary,
      length(synchronization_node_public_keys)::8,
      :erlang.list_to_binary(synchronization_node_public_keys)::binary,
      network_chains_view_hash::binary, p2p_view_hash::binary,
      serialized_contract_context::bitstring, DateTime.to_unix(ref_timestamp, :millisecond)::64>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)

    {welcome_node_public_key, <<nb_synchronization_nodes::8, rest::bitstring>>} =
      Utils.deserialize_public_key(rest)

    {synchronization_node_public_keys, rest} =
      Utils.deserialize_public_key_list(rest, nb_synchronization_nodes, [])

    <<network_chains_view_hash::binary-size(32), p2p_view_hash::binary-size(32), rest::bitstring>> =
      rest

    {contract_context, <<ref_timestamp::64, rest::bitstring>>} =
      case rest do
        <<0::8, rest::bitstring>> -> {nil, rest}
        <<1::8, rest::bitstring>> -> Contract.Context.deserialize(rest)
      end

    {%__MODULE__{
       transaction: tx,
       welcome_node_public_key: welcome_node_public_key,
       synchronization_node_public_keys: synchronization_node_public_keys,
       network_chains_view_hash: network_chains_view_hash,
       p2p_view_hash: p2p_view_hash,
       contract_context: contract_context,
       ref_timestamp: DateTime.from_unix!(ref_timestamp, :millisecond)
     }, rest}
  end

  defp check_ref_timestamp(ref_timestamp) do
    if DateTime.diff(DateTime.utc_now(), ref_timestamp, :millisecond) <= @ref_timestamp_drift,
      do: :ok,
      else: {:error, :invalid_ref_timestamp}
  end

  defp check_not_already_mining(address) do
    if Mining.processing?(address) do
      {:error, :transaction_already_mining}
    else
      :ok
    end
  end

  defp check_current_node_is_elected(synchronization_nodes) do
    node_key = Crypto.first_node_public_key()

    if Enum.any?(synchronization_nodes, &(&1 == node_key)),
      do: :ok,
      else: {:error, :current_node_not_elected}
  end

  defp check_valid_synchronization_nodes(synchronization_nodes, validation_nodes) do
    if Enum.all?(synchronization_nodes, &Utils.key_in_node_list?(validation_nodes, &1)),
      do: :ok,
      else: {:error, :invalid_synchronization_nodes_election}
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
