defmodule Uniris.P2P.Message do
  @moduledoc """
  Provide functions to encode and decode P2P messages using a custom binary protocol
  """
  alias Uniris.Account

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.Summary

  alias Uniris.Contracts

  alias Uniris.Crypto

  alias Uniris.Mining

  alias Uniris.P2P

  alias __MODULE__.AcknowledgeStorage
  alias __MODULE__.AddBeaconSlotProof
  alias __MODULE__.AddMiningContext
  alias __MODULE__.Balance
  alias __MODULE__.BatchRequests
  alias __MODULE__.BatchResponses
  alias __MODULE__.BootstrappingNodes
  alias __MODULE__.CrossValidate
  alias __MODULE__.CrossValidationDone
  alias __MODULE__.EncryptedStorageNonce
  alias __MODULE__.FirstPublicKey
  alias __MODULE__.GetBalance
  alias __MODULE__.GetBeaconSlot
  alias __MODULE__.GetBeaconSummary
  alias __MODULE__.GetBootstrappingNodes
  alias __MODULE__.GetFirstPublicKey
  alias __MODULE__.GetLastTransaction
  alias __MODULE__.GetLastTransactionAddress
  alias __MODULE__.GetP2PView
  alias __MODULE__.GetStorageNonce
  alias __MODULE__.GetTransaction
  alias __MODULE__.GetTransactionChain
  alias __MODULE__.GetTransactionChainLength
  alias __MODULE__.GetTransactionInputs
  alias __MODULE__.GetTransactionSummary
  alias __MODULE__.GetUnspentOutputs
  alias __MODULE__.LastTransactionAddress
  alias __MODULE__.ListNodes
  alias __MODULE__.NewTransaction
  alias __MODULE__.NodeList
  alias __MODULE__.NotFound
  alias __MODULE__.NotifyBeaconSlot
  alias __MODULE__.NotifyEndOfNodeSync
  alias __MODULE__.NotifyLastTransactionAddress
  alias __MODULE__.Ok
  alias __MODULE__.P2PView
  alias __MODULE__.ReplicateTransaction
  alias __MODULE__.StartMining
  alias __MODULE__.TransactionChainLength
  alias __MODULE__.TransactionInputList
  alias __MODULE__.TransactionList
  alias __MODULE__.UnspentOutputList

  alias Uniris.P2P.Node

  alias Uniris.PubSub

  alias Uniris.Replication

  alias Uniris.TaskSupervisor

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.CrossValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionChain.TransactionInput

  alias Uniris.Utils

  require Logger

  @type t :: request() | response()

  @type request ::
          GetBootstrappingNodes.t()
          | GetStorageNonce.t()
          | ListNodes.t()
          | GetTransaction.t()
          | GetTransactionChain.t()
          | GetUnspentOutputs.t()
          | GetP2PView.t()
          | NewTransaction.t()
          | StartMining.t()
          | AddMiningContext.t()
          | CrossValidate.t()
          | CrossValidationDone.t()
          | ReplicateTransaction.t()
          | GetLastTransaction.t()
          | GetBalance.t()
          | GetTransactionInputs.t()
          | GetTransactionChainLength.t()
          | NotifyEndOfNodeSync.t()
          | AddBeaconSlotProof.t()
          | NotifyBeaconSlot.t()
          | GetBeaconSummary.t()
          | GetBeaconSlot.t()
          | GetLastTransactionAddress.t()
          | BatchRequests.t()
          | NotifyLastTransactionAddress.t()

  @type response ::
          Ok.t()
          | NotFound.t()
          | TransactionList.t()
          | Transaction.t()
          | NodeList.t()
          | UnspentOutputList.t()
          | Balance.t()
          | EncryptedStorageNonce.t()
          | BootstrappingNodes.t()
          | P2PView.t()
          | Transaction.t()
          | Slot.t()
          | TransactionSummary.t()
          | LastTransactionAddress.t()
          | FirstPublicKey.t()
          | TransactionChainLength.t()
          | TransactionInputList.t()
          | BatchResponses.t()

  @doc """
  Serialize a message into binary

  ## Examples

      iex> Message.encode(%Ok{})
      <<255>>

      iex> %Message.GetTransaction{
      ...>  address: <<0, 40, 71, 99, 6, 218, 243, 156, 193, 63, 176, 168, 22, 226, 31, 170, 119, 122,
      ...>    13, 188, 75, 49, 171, 219, 222, 133, 86, 132, 188, 206, 233, 66, 7>>
      ...> } |> Message.encode()
      <<
      # Message type
      3,
      # Address
      0, 40, 71, 99, 6, 218, 243, 156, 193, 63, 176, 168, 22, 226, 31, 170, 119, 122,
      13, 188, 75, 49, 171, 219, 222, 133, 86, 132, 188, 206, 233, 66, 7
      >>
  """
  @spec encode(t()) :: bitstring()
  def encode(%GetBootstrappingNodes{patch: patch}) do
    <<0::8, patch::binary-size(3)>>
  end

  def encode(%GetStorageNonce{public_key: public_key}) do
    <<1::8, public_key::binary>>
  end

  def encode(%ListNodes{}) do
    <<2::8>>
  end

  def encode(%GetTransaction{address: tx_address}) do
    <<3::8, tx_address::binary>>
  end

  def encode(%GetTransactionChain{address: tx_address}) do
    <<4::8, tx_address::binary>>
  end

  def encode(%GetUnspentOutputs{address: tx_address}) do
    <<5::8, tx_address::binary>>
  end

  def encode(%NewTransaction{transaction: tx}) do
    <<6::8, Transaction.serialize(tx)::binary>>
  end

  def encode(%StartMining{
        transaction: tx,
        welcome_node_public_key: welcome_node_public_key,
        validation_node_public_keys: validation_node_public_keys
      }) do
    <<7::8, Transaction.serialize(tx)::binary, welcome_node_public_key::binary,
      length(validation_node_public_keys)::8,
      :erlang.list_to_binary(validation_node_public_keys)::binary>>
  end

  def encode(%AddMiningContext{
        address: address,
        validation_node_public_key: validation_node_public_key,
        validation_nodes_view: validation_nodes_view,
        chain_storage_nodes_view: chain_storage_nodes_view,
        beacon_storage_nodes_view: beacon_storage_nodes_view,
        previous_storage_nodes_public_keys: previous_storage_nodes_public_keys
      }) do
    <<8::8, address::binary, validation_node_public_key::binary,
      length(previous_storage_nodes_public_keys)::8,
      :erlang.list_to_binary(previous_storage_nodes_public_keys)::binary,
      bit_size(validation_nodes_view)::8, validation_nodes_view::bitstring,
      bit_size(chain_storage_nodes_view)::8, chain_storage_nodes_view::bitstring,
      bit_size(beacon_storage_nodes_view)::8, beacon_storage_nodes_view::bitstring>>
  end

  def encode(%CrossValidate{
        address: address,
        validation_stamp: stamp,
        replication_tree: replication_tree
      }) do
    <<9::8, address::binary, ValidationStamp.serialize(stamp)::bitstring,
      length(replication_tree)::8, bit_size(List.first(replication_tree)),
      :erlang.list_to_bitstring(replication_tree)::bitstring>>
  end

  def encode(%CrossValidationDone{address: address, cross_validation_stamp: stamp}) do
    <<10::8, address::binary, CrossValidationStamp.serialize(stamp)::bitstring>>
  end

  def encode(%ReplicateTransaction{transaction: tx}) do
    <<11::8, Transaction.serialize(tx)::bitstring>>
  end

  def encode(%AcknowledgeStorage{address: address}) do
    <<12::8, address::binary>>
  end

  def encode(%GetBeaconSummary{subset: subset, date: date}) do
    <<13::8, subset::binary, DateTime.to_unix(date)::32>>
  end

  def encode(%NotifyEndOfNodeSync{node_public_key: public_key, timestamp: timestamp}) do
    <<14::8, public_key::binary, DateTime.to_unix(timestamp)::32>>
  end

  def encode(%GetLastTransaction{address: address}) do
    <<15::8, address::binary>>
  end

  def encode(%GetBalance{address: address}) do
    <<16::8, address::binary>>
  end

  def encode(%GetTransactionInputs{address: address}) do
    <<17::8, address::binary>>
  end

  def encode(%GetTransactionChainLength{address: address}) do
    <<18::8, address::binary>>
  end

  def encode(%GetP2PView{node_public_keys: node_public_keys}) do
    <<19::8, length(node_public_keys)::16, :erlang.list_to_binary(node_public_keys)::binary>>
  end

  def encode(%GetFirstPublicKey{address: address}) do
    <<20::8, address::binary>>
  end

  def encode(%GetLastTransactionAddress{address: address}) do
    <<21::8, address::binary>>
  end

  def encode(%NotifyLastTransactionAddress{address: address, previous_address: previous_address}) do
    <<22::8, address::binary, previous_address::binary>>
  end

  def encode(%GetTransactionSummary{address: address}) do
    <<23::8, address::binary>>
  end

  def encode(%NotifyBeaconSlot{slot: slot}) do
    <<24::8, Slot.serialize(slot)::bitstring>>
  end

  def encode(%AddBeaconSlotProof{
        subset: subset,
        digest: digest,
        public_key: public_key,
        signature: signature
      }) do
    <<25::8, subset::binary, digest::binary, public_key::binary, byte_size(signature)::8,
      signature::binary>>
  end

  def encode(%GetBeaconSlot{subset: subset, slot_time: slot_time}) do
    <<26::8, subset::binary, DateTime.to_unix(slot_time)::32>>
  end

  def encode(%BatchRequests{requests: requests}) do
    <<27::8, length(requests)::16,
      Enum.map(requests, &encode/1) |> :erlang.list_to_bitstring()::bitstring>>
  end

  def encode(%BatchResponses{responses: responses}) do
    responses_binary =
      Enum.map(responses, fn {index, response} ->
        <<index::16, encode(response)::bitstring>>
      end)
      |> :erlang.list_to_bitstring()

    <<238::8, length(responses)::16, responses_binary::bitstring>>
  end

  def encode(tx_summary = %TransactionSummary{}) do
    <<239::8, TransactionSummary.serialize(tx_summary)::binary>>
  end

  def encode(summary = %Summary{}) do
    <<240::8, Summary.serialize(summary)::binary>>
  end

  def encode(slot = %Slot{}) do
    <<241::8, Slot.serialize(slot)::binary>>
  end

  def encode(%LastTransactionAddress{address: address}) do
    <<242::8, address::binary>>
  end

  def encode(%FirstPublicKey{public_key: public_key}) do
    <<243::8, public_key::binary>>
  end

  def encode(%P2PView{nodes_view: view}) do
    <<244::8, bit_size(view)::8, view::bitstring>>
  end

  def encode(%TransactionInputList{inputs: inputs}) do
    inputs_bin =
      Enum.map(inputs, &TransactionInput.serialize/1)
      |> :erlang.list_to_bitstring()

    <<245::8, length(inputs)::16, inputs_bin::bitstring>>
  end

  def encode(%TransactionChainLength{length: length}) do
    <<246::8, length::32>>
  end

  def encode(%BootstrappingNodes{new_seeds: new_seeds, closest_nodes: closest_nodes}) do
    new_seeds_bin =
      new_seeds
      |> Enum.map(&Node.serialize/1)
      |> :erlang.list_to_bitstring()

    closest_nodes_bin =
      closest_nodes
      |> Enum.map(&Node.serialize/1)
      |> :erlang.list_to_bitstring()

    <<247::8, length(new_seeds)::8, new_seeds_bin::bitstring, length(closest_nodes)::8,
      closest_nodes_bin::bitstring>>
  end

  def encode(%EncryptedStorageNonce{digest: digest}) do
    <<248::8, byte_size(digest)::8, digest::binary>>
  end

  def encode(%Balance{uco: uco_balance, nft: nft_balances}) do
    nft_balances_binary =
      nft_balances
      |> Enum.reduce([], fn {nft_address, amount}, acc ->
        [<<nft_address::binary, amount::float>> | acc]
      end)
      |> Enum.reverse()
      |> :erlang.list_to_binary()

    <<249::8, uco_balance::float, map_size(nft_balances)::16, nft_balances_binary::binary>>
  end

  def encode(%NodeList{nodes: nodes}) do
    nodes_bin =
      nodes
      |> Enum.map(&Node.serialize/1)
      |> :erlang.list_to_bitstring()

    <<250::8, length(nodes)::16, nodes_bin::bitstring>>
  end

  def encode(%UnspentOutputList{unspent_outputs: unspent_outputs}) do
    unspent_outputs_bin =
      unspent_outputs
      |> Enum.map(&UnspentOutput.serialize/1)
      |> :erlang.list_to_binary()

    <<251::8, length(unspent_outputs)::32, unspent_outputs_bin::binary>>
  end

  def encode(%TransactionList{transactions: transactions}) do
    transaction_bin =
      transactions
      |> Enum.map(&Transaction.serialize/1)
      |> :erlang.list_to_bitstring()

    <<252::8, length(transactions)::32, transaction_bin::bitstring>>
  end

  def encode(tx = %Transaction{}) do
    <<253::8, Transaction.serialize(tx)::bitstring>>
  end

  def encode(%NotFound{}) do
    <<254::8>>
  end

  def encode(%Ok{}) do
    <<255::8>>
  end

  @doc """
  Decode an encoded message
  """
  @spec decode(bitstring()) :: {t(), bitstring}
  def decode(<<0::8, patch::binary-size(3), rest::bitstring>>) do
    {
      %GetBootstrappingNodes{patch: patch},
      rest
    }
  end

  def decode(<<1::8, curve_id::8, rest::bitstring>>) do
    key_size = Crypto.key_size(curve_id)
    <<public_key::binary-size(key_size), rest::bitstring>> = rest

    {
      %GetStorageNonce{
        public_key: <<curve_id::8, public_key::binary>>
      },
      rest
    }
  end

  def decode(<<2::8, rest::bitstring>>) do
    {%ListNodes{}, rest}
  end

  def decode(<<3::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)

    {
      %GetTransaction{address: address},
      rest
    }
  end

  def decode(<<4::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)
    {%GetTransactionChain{address: address}, rest}
  end

  def decode(<<5::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)
    {%GetUnspentOutputs{address: address}, rest}
  end

  def decode(<<6::8, rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)
    {%NewTransaction{transaction: tx}, rest}
  end

  def decode(<<7::8, rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)

    {welcome_node_public_key, <<nb_validation_nodes::8, rest::bitstring>>} =
      deserialize_public_key(rest)

    {validation_node_public_keys, rest} =
      deserialize_public_key_list(rest, nb_validation_nodes, [])

    {%StartMining{
       transaction: tx,
       welcome_node_public_key: welcome_node_public_key,
       validation_node_public_keys: validation_node_public_keys
     }, rest}
  end

  def decode(<<8::8, hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<address::binary-size(hash_size), curve_id::8, rest::bitstring>> = rest
    key_size = Crypto.key_size(curve_id)
    <<key::binary-size(key_size), nb_previous_storage_nodes::8, rest::bitstring>> = rest

    {previous_storage_nodes_keys, rest} =
      deserialize_public_key_list(rest, nb_previous_storage_nodes, [])

    <<validation_nodes_view_size::8,
      validation_nodes_view::bitstring-size(validation_nodes_view_size),
      chain_storage_nodes_view_size::8,
      chain_storage_nodes_view::bitstring-size(chain_storage_nodes_view_size),
      beacon_storage_nodes_view_size::8,
      beacon_storage_nodes_view::bitstring-size(beacon_storage_nodes_view_size),
      rest::bitstring>> = rest

    {%AddMiningContext{
       address: <<hash_id::8, address::binary>>,
       validation_node_public_key: <<curve_id::8, key::binary>>,
       validation_nodes_view: validation_nodes_view,
       chain_storage_nodes_view: chain_storage_nodes_view,
       beacon_storage_nodes_view: beacon_storage_nodes_view,
       previous_storage_nodes_public_keys: previous_storage_nodes_keys
     }, rest}
  end

  def decode(<<9::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)
    {validation_stamp, rest} = ValidationStamp.deserialize(rest)

    <<nb_sequences::8, sequence_size::8, rest::bitstring>> = rest
    {replication_tree, rest} = deserialize_bit_sequences(rest, nb_sequences, sequence_size, [])

    {%CrossValidate{
       address: address,
       validation_stamp: validation_stamp,
       replication_tree: replication_tree
     }, rest}
  end

  def decode(<<10::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)
    {stamp, rest} = CrossValidationStamp.deserialize(rest)

    {%CrossValidationDone{
       address: address,
       cross_validation_stamp: stamp
     }, rest}
  end

  def decode(<<11::8, rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)

    {%ReplicateTransaction{
       transaction: tx
     }, rest}
  end

  def decode(<<12::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)

    {%AcknowledgeStorage{
       address: address
     }, rest}
  end

  def decode(<<13::8, subset::binary-size(1), timestamp::32, rest::bitstring>>) do
    {%GetBeaconSummary{
       date: DateTime.from_unix!(timestamp),
       subset: subset
     }, rest}
  end

  def decode(<<14::8, rest::bitstring>>) do
    {public_key, <<timestamp::32, rest::bitstring>>} = deserialize_public_key(rest)

    {%NotifyEndOfNodeSync{
       node_public_key: public_key,
       timestamp: DateTime.from_unix!(timestamp)
     }, rest}
  end

  def decode(<<15::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)

    {%GetLastTransaction{address: address}, rest}
  end

  def decode(<<16::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)

    {%GetBalance{address: address}, rest}
  end

  def decode(<<17::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)

    {%GetTransactionInputs{address: address}, rest}
  end

  def decode(<<18::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)

    {%GetTransactionChainLength{address: address}, rest}
  end

  def decode(<<19::8, nb_node_public_keys::16, rest::bitstring>>) do
    {public_keys, rest} = deserialize_public_key_list(rest, nb_node_public_keys, [])
    {%GetP2PView{node_public_keys: public_keys}, rest}
  end

  def decode(<<20::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)

    {%GetFirstPublicKey{
       address: address
     }, rest}
  end

  def decode(<<21::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)

    {%GetLastTransactionAddress{
       address: address
     }, rest}
  end

  def decode(<<22::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)
    {previous_address, rest} = deserialize_hash(rest)

    {%NotifyLastTransactionAddress{address: address, previous_address: previous_address}, rest}
  end

  def decode(<<23::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)
    {%GetTransactionSummary{address: address}, rest}
  end

  def decode(<<24::8, rest::bitstring>>) do
    {slot, rest} = Slot.deserialize(rest)
    {%NotifyBeaconSlot{slot: slot}, rest}
  end

  def decode(<<25::8, subset::binary-size(1), rest::bitstring>>) do
    {digest, rest} = deserialize_hash(rest)

    {public_key, <<signature_size::8, signature::binary-size(signature_size), rest::bitstring>>} =
      deserialize_public_key(rest)

    {%AddBeaconSlotProof{
       subset: subset,
       digest: digest,
       public_key: public_key,
       signature: signature
     }, rest}
  end

  def decode(<<26::8, subset::binary-size(1), timestamp::32, rest::bitstring>>) do
    {%GetBeaconSlot{subset: subset, slot_time: DateTime.from_unix!(timestamp)}, rest}
  end

  def decode(<<27::8, nb_requests::16, rest::bitstring>>) do
    {requests, rest} = deserialize_batched_requests(rest, nb_requests, [])

    {%BatchRequests{
       requests: requests
     }, rest}
  end

  def decode(<<238::8, nb_responses::16, rest::bitstring>>) do
    {responses, rest} = deserialize_batched_responses(rest, nb_responses, [])

    {%BatchResponses{
       responses: responses
     }, rest}
  end

  def decode(<<239::8, rest::bitstring>>) do
    TransactionSummary.deserialize(rest)
  end

  def decode(<<240::8, rest::bitstring>>) do
    Summary.deserialize(rest)
  end

  def decode(<<241::8, rest::bitstring>>) do
    Slot.deserialize(rest)
  end

  def decode(<<242::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)
    {%LastTransactionAddress{address: address}, rest}
  end

  def decode(<<243::8, rest::bitstring>>) do
    {public_key, rest} = deserialize_public_key(rest)
    {%FirstPublicKey{public_key: public_key}, rest}
  end

  def decode(<<244::8, view_size::8, rest::bitstring>>) do
    {nodes_view, rest} = Utils.unwrap_bitstring(rest, view_size)
    {%P2PView{nodes_view: nodes_view}, rest}
  end

  def decode(<<245::8, nb_inputs::16, rest::bitstring>>) do
    {inputs, rest} = deserialize_transaction_inputs(rest, nb_inputs, [])

    {%TransactionInputList{
       inputs: inputs
     }, rest}
  end

  def decode(<<246::8, length::32, rest::bitstring>>) do
    {%TransactionChainLength{
       length: length
     }, rest}
  end

  def decode(<<247::8, nb_new_seeds::8, rest::bitstring>>) do
    {new_seeds, <<nb_closest_nodes::8, rest::bitstring>>} =
      deserialize_node_list(rest, nb_new_seeds, [])

    {closest_nodes, rest} = deserialize_node_list(rest, nb_closest_nodes, [])

    {%BootstrappingNodes{
       new_seeds: new_seeds,
       closest_nodes: closest_nodes
     }, rest}
  end

  def decode(<<248::8, digest_size::8, digest::binary-size(digest_size), rest::bitstring>>) do
    {%EncryptedStorageNonce{
       digest: digest
     }, rest}
  end

  def decode(<<249::8, uco_balance::float, nb_nft_balances::16, rest::bitstring>>) do
    {nft_balances, rest} = deserialize_nft_balances(rest, nb_nft_balances, %{})

    {%Balance{
       uco: uco_balance,
       nft: nft_balances
     }, rest}
  end

  def decode(<<250::8, nb_nodes::16, rest::bitstring>>) do
    {nodes, rest} = deserialize_node_list(rest, nb_nodes, [])
    {%NodeList{nodes: nodes}, rest}
  end

  def decode(<<251::8, nb_unspent_outputs::32, rest::bitstring>>) do
    {unspent_outputs, rest} = deserialize_unspent_output_list(rest, nb_unspent_outputs, [])
    {%UnspentOutputList{unspent_outputs: unspent_outputs}, rest}
  end

  def decode(<<252::8, nb_transactions::32, rest::bitstring>>) do
    {transactions, rest} = deserialize_tx_list(rest, nb_transactions, [])
    {%TransactionList{transactions: transactions}, rest}
  end

  def decode(<<253::8, rest::bitstring>>) do
    Transaction.deserialize(rest)
  end

  def decode(<<254::8, rest::bitstring>>) do
    {%NotFound{}, rest}
  end

  def decode(<<255::8, rest::bitstring>>) do
    {%Ok{}, rest}
  end

  defp deserialize_node_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_node_list(rest, nb_nodes, acc) when length(acc) == nb_nodes do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_node_list(rest, nb_nodes, acc) do
    {node, rest} = Node.deserialize(rest)
    deserialize_node_list(rest, nb_nodes, [node | acc])
  end

  defp deserialize_tx_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_tx_list(rest, nb_transactions, acc) when length(acc) == nb_transactions do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_tx_list(rest, nb_transactions, acc) do
    {tx, rest} = Transaction.deserialize(rest)
    deserialize_tx_list(rest, nb_transactions, [tx | acc])
  end

  defp deserialize_public_key_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_public_key_list(rest, nb_keys, acc) when length(acc) == nb_keys do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_public_key_list(rest, nb_keys, acc) do
    {public_key, rest} = deserialize_public_key(rest)
    deserialize_public_key_list(rest, nb_keys, [public_key | acc])
  end

  defp deserialize_unspent_output_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_unspent_output_list(rest, nb_unspent_outputs, acc)
       when length(acc) == nb_unspent_outputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_unspent_output_list(rest, nb_unspent_outputs, acc) do
    {unspent_output, rest} = UnspentOutput.deserialize(rest)
    deserialize_unspent_output_list(rest, nb_unspent_outputs, [unspent_output | acc])
  end

  defp deserialize_hash(<<hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<hash::binary-size(hash_size), rest::bitstring>> = rest
    {<<hash_id::8, hash::binary>>, rest}
  end

  defp deserialize_public_key(<<curve_id::8, rest::bitstring>>) do
    key_size = Crypto.key_size(curve_id)
    <<public_key::binary-size(key_size), rest::bitstring>> = rest
    {<<curve_id::8, public_key::binary>>, rest}
  end

  defp deserialize_bit_sequences(rest, nb_sequences, _sequence_size, acc)
       when length(acc) == nb_sequences do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_bit_sequences(rest, nb_sequences, sequence_size, acc) do
    <<sequence::bitstring-size(sequence_size), rest::bitstring>> = rest
    deserialize_bit_sequences(rest, nb_sequences, sequence_size, [sequence | acc])
  end

  defp deserialize_transaction_inputs(rest, 0, _acc), do: {[], rest}

  defp deserialize_transaction_inputs(rest, nb_inputs, acc) when length(acc) == nb_inputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_transaction_inputs(rest, nb_inputs, acc) do
    {input, rest} = TransactionInput.deserialize(rest)
    deserialize_transaction_inputs(rest, nb_inputs, [input | acc])
  end

  defp deserialize_nft_balances(rest, 0, _acc), do: {%{}, rest}

  defp deserialize_nft_balances(rest, nft_balances, acc) when map_size(acc) == nft_balances do
    {acc, rest}
  end

  defp deserialize_nft_balances(rest, nb_nft_balances, acc) do
    {nft_address, <<amount::float, rest::bitstring>>} = deserialize_hash(rest)
    deserialize_nft_balances(rest, nb_nft_balances, Map.put(acc, nft_address, amount))
  end

  defp deserialize_batched_requests(rest, nb_requests, acc) when nb_requests == length(acc) do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_batched_requests(rest, 0, _acc), do: {[], rest}

  defp deserialize_batched_requests(rest, nb_requests, acc) do
    {request, rest} = decode(rest)
    deserialize_batched_requests(rest, nb_requests, [request | acc])
  end

  defp deserialize_batched_responses(rest, 0, _acc), do: {[], rest}

  defp deserialize_batched_responses(<<index::16, rest::bitstring>>, nb_responses, acc) do
    {response, rest} = decode(rest)
    deserialize_batched_responses(rest, nb_responses, [{index, response} | acc])
  end

  defp deserialize_batched_responses(rest, nb_responses, acc) when nb_responses == length(acc) do
    {Enum.reverse(acc), rest}
  end

  # TODO: support streaming
  @doc """
  Handle a P2P message by processing it through the dedicated context
  """
  @spec process(request()) :: response()
  def process(%GetBootstrappingNodes{patch: patch}) do
    top_nodes = P2P.list_nodes(authorized?: true, availability: :local)

    closest_nodes =
      top_nodes
      |> P2P.nearest_nodes(patch)
      |> Enum.take(5)

    %BootstrappingNodes{
      new_seeds: Enum.take_random(top_nodes, 5),
      closest_nodes: closest_nodes
    }
  end

  def process(%GetStorageNonce{public_key: public_key}) do
    %EncryptedStorageNonce{
      digest: Crypto.encrypt_storage_nonce(public_key)
    }
  end

  def process(%ListNodes{}) do
    %NodeList{
      nodes: P2P.list_nodes()
    }
  end

  def process(%NewTransaction{transaction: tx}) do
    :ok = Uniris.send_new_transaction(tx)
    %Ok{}
  end

  def process(%GetTransaction{address: tx_address}) do
    case TransactionChain.get_transaction(tx_address) do
      {:ok, tx} ->
        tx

      _ ->
        %NotFound{}
    end
  end

  def process(%GetTransactionChain{address: tx_address}) do
    %TransactionList{
      transactions:
        tx_address
        |> TransactionChain.get()
        |> Enum.to_list()
    }
  end

  def process(%GetUnspentOutputs{address: tx_address}) do
    %UnspentOutputList{
      unspent_outputs: Account.get_unspent_outputs(tx_address)
    }
  end

  def process(%GetP2PView{node_public_keys: node_public_keys}) do
    nodes =
      Enum.map(node_public_keys, fn key ->
        {:ok, node} = P2P.get_node_info(key)
        node
      end)

    view = P2P.nodes_availability_as_bits(nodes)
    %P2PView{nodes_view: view}
  end

  def process(%StartMining{
        transaction: tx = %Transaction{},
        welcome_node_public_key: welcome_node_public_key,
        validation_node_public_keys: validation_nodes
      })
      when length(validation_nodes) > 0 do
    with :ok <- Mining.validate_pending_transaction(tx),
         true <- Mining.valid_election?(tx, validation_nodes) do
      {:ok, _} = Mining.start(tx, welcome_node_public_key, validation_nodes)
      %Ok{}
    else
      _ ->
        raise "Invalid transaction mining request"
    end
  end

  def process(%AddMiningContext{
        address: tx_address,
        validation_node_public_key: validation_node,
        previous_storage_nodes_public_keys: previous_storage_nodes_public_keys,
        validation_nodes_view: validation_nodes_view,
        chain_storage_nodes_view: chain_storage_nodes_view,
        beacon_storage_nodes_view: beacon_storage_nodes_view
      }) do
    :ok =
      Mining.add_mining_context(
        tx_address,
        validation_node,
        previous_storage_nodes_public_keys,
        validation_nodes_view,
        chain_storage_nodes_view,
        beacon_storage_nodes_view
      )

    %Ok{}
  end

  def process(%ReplicateTransaction{transaction: tx}) do
    roles =
      [
        chain: Replication.chain_storage_node?(tx, Crypto.node_public_key()),
        beacon: Replication.beacon_storage_node?(tx, Crypto.node_public_key()),
        IO: Replication.io_storage_node?(tx, Crypto.node_public_key())
      ]
      |> Utils.get_keys_from_value_match(true)

    case roles do
      [] ->
        %Ok{}

      replication_roles ->
        Logger.info("Replicate transaction", transaction: Base.encode16(tx.address))

        Task.Supervisor.start_child(
          TaskSupervisor,
          fn -> Replication.process_transaction(tx, replication_roles, ack_storage?: true) end,
          restart: :transient
        )

        %Ok{}
    end
  end

  def process(%AcknowledgeStorage{address: tx_address}) do
    :ok = PubSub.notify_new_transaction(tx_address)
    %Ok{}
  end

  def process(%CrossValidate{
        address: tx_address,
        validation_stamp: stamp,
        replication_tree: replication_tree
      }) do
    :ok = Mining.cross_validate(tx_address, stamp, replication_tree)
    %Ok{}
  end

  def process(%CrossValidationDone{address: tx_address, cross_validation_stamp: stamp}) do
    :ok = Mining.add_cross_validation_stamp(tx_address, stamp)
    %Ok{}
  end

  def process(%GetBeaconSummary{date: date, subset: subset}) do
    case BeaconChain.get_summary(subset, date) do
      {:ok, summary} ->
        summary

      _ ->
        %NotFound{}
    end
  end

  def process(%NotifyEndOfNodeSync{node_public_key: public_key, timestamp: timestamp}) do
    :ok = BeaconChain.add_end_of_node_sync(public_key, timestamp)
    %Ok{}
  end

  def process(%GetLastTransaction{address: address}) do
    case TransactionChain.get_last_transaction(address) do
      {:ok, tx} ->
        tx

      {:error, :transaction_not_exists} ->
        %NotFound{}

      {:error, :invalid_transaction} ->
        %NotFound{}
    end
  end

  def process(%GetBalance{address: address}) do
    %{uco: uco, nft: nft} = Account.get_balance(address)

    %Balance{
      uco: uco,
      nft: nft
    }
  end

  def process(%GetTransactionInputs{address: address}) do
    ledger_inputs = Account.get_inputs(address)

    contract_inputs =
      address
      |> Contracts.list_contract_transactions()
      |> Enum.map(fn {address, timestamp} ->
        %TransactionInput{from: address, type: :call, timestamp: timestamp}
      end)

    %TransactionInputList{inputs: ledger_inputs ++ contract_inputs}
  end

  def process(%GetTransactionChainLength{address: address}) do
    %TransactionChainLength{
      length: TransactionChain.size(address)
    }
  end

  def process(%GetFirstPublicKey{address: address}) do
    case TransactionChain.get_first_transaction(address, [:previous_public_key]) do
      {:ok, %Transaction{previous_public_key: key}} ->
        %FirstPublicKey{public_key: key}

      {:error, :transaction_not_exists} ->
        %NotFound{}
    end
  end

  def process(%GetLastTransactionAddress{address: address}) do
    address = TransactionChain.get_last_address(address)
    %LastTransactionAddress{address: address}
  end

  def process(%NotifyLastTransactionAddress{
        address: address,
        previous_address: previous_address
      }) do
    :ok = Replication.acknowledge_previous_storage_nodes(address, previous_address)
    %Ok{}
  end

  def process(%GetTransactionSummary{address: address}) do
    case TransactionChain.get_transaction(address, [
           :address,
           :type,
           :timestamp,
           validation_stamp: [:node_movements, :transaction_movements]
         ]) do
      {:ok, tx} ->
        TransactionSummary.from_transaction(tx)

      _ ->
        %NotFound{}
    end
  end

  def process(%GetBeaconSlot{subset: subset, slot_time: slot_time}) do
    case BeaconChain.get_slot(subset, slot_time) do
      {:ok, slot = %Slot{}} ->
        slot

      {:error, :not_found} ->
        %NotFound{}
    end
  end

  def process(%NotifyBeaconSlot{slot: slot}) do
    Task.start(fn -> BeaconChain.register_slot(slot) end)
    %Ok{}
  end

  def process(%AddBeaconSlotProof{
        subset: subset,
        digest: digest,
        public_key: node_public_key,
        signature: signature
      }) do
    :ok = BeaconChain.add_slot_proof(subset, digest, node_public_key, signature)
    %Ok{}
  end

  def process(%BatchRequests{requests: requests}) do
    responses =
      requests
      |> Enum.with_index()
      |> Enum.map(fn {request, index} ->
        {index, process(request)}
      end)

    %BatchResponses{responses: responses}
  end
end
