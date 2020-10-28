defmodule Uniris.P2P.Message do
  @moduledoc """
  Provide functions to encode and decode P2P messages using a custom binary protocol
  """
  alias Uniris.Account

  alias Uniris.BeaconChain.Slot, as: BeaconSlot
  alias Uniris.BeaconChain.Slot.NodeInfo
  alias Uniris.BeaconChain.Subset, as: BeaconSubset

  alias Uniris.Crypto

  alias Uniris.Mining

  alias Uniris.P2P

  alias __MODULE__.AcknowledgeStorage
  alias __MODULE__.AddMiningContext
  alias __MODULE__.AddNodeInfo
  alias __MODULE__.Balance
  alias __MODULE__.BeaconSlotList
  alias __MODULE__.BootstrappingNodes
  alias __MODULE__.CrossValidate
  alias __MODULE__.CrossValidationDone
  alias __MODULE__.EncryptedStorageNonce
  alias __MODULE__.FirstPublicKey
  alias __MODULE__.GetBalance
  alias __MODULE__.GetBeaconSlots
  alias __MODULE__.GetBootstrappingNodes
  alias __MODULE__.GetFirstPublicKey
  alias __MODULE__.GetLastTransaction
  alias __MODULE__.GetP2PView
  alias __MODULE__.GetStorageNonce
  alias __MODULE__.GetTransaction
  alias __MODULE__.GetTransactionChain
  alias __MODULE__.GetTransactionChainLength
  alias __MODULE__.GetTransactionInputs
  alias __MODULE__.GetUnspentOutputs
  alias __MODULE__.ListNodes
  alias __MODULE__.NewTransaction
  alias __MODULE__.NodeList
  alias __MODULE__.NotFound
  alias __MODULE__.Ok
  alias __MODULE__.P2PView
  alias __MODULE__.ReplicateTransaction
  alias __MODULE__.StartMining
  alias __MODULE__.SubscribeTransactionValidation
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

  @type t() ::
          GetBootstrappingNodes.t()
          | GetStorageNonce.t()
          | ListNodes.t()
          | GetTransaction.t()
          | GetTransactionChain.t()
          | GetUnspentOutput.t()
          | GetP2PView.t()
          | NewTransaction.t()
          | StartMining.t()
          | AddMiningContext.t()
          | CrossValidate.t()
          | CrossValidationDone.t()
          | ReplicateTransaction.t()
          | GetBeaconSlots.t()
          | AddNodeInfo.t()
          | GetLastTransaction.t()
          | GetBalance.t()
          | GetTransactionInputs.t()
          | GetTransactionChainLength.t()
          | TransactionChainLength.t()
          | Ok.t()
          | NotFound.t()
          | BeaconSlotList.t()
          | TransactionList.t()
          | Transaction.t()
          | NodeList.t()
          | UnspentOutputList.t()
          | Balance.t()
          | EncryptedStorageNonce.t()
          | BootstrappingNodes.t()
          | P2PView.t()
          | SubscribeTransactionValidation.t()

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

  def encode(%GetBeaconSlots{subset: subset, last_sync_date: last_sync_date}) do
    <<13::8, DateTime.to_unix(last_sync_date)::32, subset::binary>>
  end

  def encode(%AddNodeInfo{subset: subset, node_info: node_info}) do
    <<14::8, subset::binary, NodeInfo.serialize(node_info)::bitstring>>
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

  def encode(%SubscribeTransactionValidation{address: address}) do
    <<20::8, address::binary>>
  end

  def encode(%GetFirstPublicKey{address: address}) do
    <<21::8, address::binary>>
  end

  def encode(%FirstPublicKey{public_key: public_key}) do
    <<242::8, public_key::binary>>
  end

  def encode(%P2PView{nodes_view: view}) do
    <<243::8, bit_size(view)::8, view::bitstring>>
  end

  def encode(%TransactionInputList{inputs: inputs}) do
    inputs_bin =
      Enum.map(inputs, &TransactionInput.serialize/1)
      |> :erlang.list_to_bitstring()

    <<244::8, length(inputs)::16, inputs_bin::bitstring>>
  end

  def encode(%TransactionChainLength{length: length}) do
    <<245::8, length::32>>
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

    <<246::8, length(new_seeds)::8, new_seeds_bin::bitstring, length(closest_nodes)::8,
      closest_nodes_bin::bitstring>>
  end

  def encode(%EncryptedStorageNonce{digest: digest}) do
    <<247::8, digest::binary>>
  end

  def encode(%Balance{uco: uco_balance}) do
    <<248::8, uco_balance::float>>
  end

  def encode(%BeaconSlotList{slots: slots}) do
    slots_bin =
      slots
      |> Enum.map(&BeaconSlot.serialize/1)
      |> :erlang.list_to_bitstring()

    <<249::8, length(slots)::16, slots_bin::bitstring>>
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
  @spec decode(bitstring()) :: t()
  def decode(<<0::8, patch::binary-size(3)>>) do
    %GetBootstrappingNodes{
      patch: patch
    }
  end

  def decode(<<1::8, curve_id::8, rest::bitstring>>) do
    key_size = Crypto.key_size(curve_id)
    <<public_key::binary-size(key_size), _::bitstring>> = rest

    %GetStorageNonce{
      public_key: <<curve_id::8, public_key::binary>>
    }
  end

  def decode(<<2::8>>) do
    %ListNodes{}
  end

  def decode(<<3::8, rest::bitstring>>) do
    {address, _} = deserialize_hash(rest)

    %GetTransaction{
      address: address
    }
  end

  def decode(<<4::8, rest::bitstring>>) do
    {address, _} = deserialize_hash(rest)

    %GetTransactionChain{
      address: address
    }
  end

  def decode(<<5::8, rest::bitstring>>) do
    {address, _} = deserialize_hash(rest)

    %GetUnspentOutputs{
      address: address
    }
  end

  def decode(<<6::8, rest::bitstring>>) do
    {tx, _} = Transaction.deserialize(rest)

    %NewTransaction{
      transaction: tx
    }
  end

  def decode(<<7::8, rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)

    {welcome_node_public_key, <<nb_validation_nodes::8, rest::bitstring>>} =
      deserialize_public_key(rest)

    {validation_node_public_keys, _} = deserialize_public_key_list(rest, nb_validation_nodes, [])

    %StartMining{
      transaction: tx,
      welcome_node_public_key: welcome_node_public_key,
      validation_node_public_keys: validation_node_public_keys
    }
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
      _::bitstring>> = rest

    %AddMiningContext{
      address: <<hash_id::8, address::binary>>,
      validation_node_public_key: <<curve_id::8, key::binary>>,
      validation_nodes_view: validation_nodes_view,
      chain_storage_nodes_view: chain_storage_nodes_view,
      beacon_storage_nodes_view: beacon_storage_nodes_view,
      previous_storage_nodes_public_keys: previous_storage_nodes_keys
    }
  end

  def decode(<<9::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)
    {validation_stamp, rest} = ValidationStamp.deserialize(rest)

    <<nb_sequences::8, sequence_size::8, rest::bitstring>> = rest
    {replication_tree, _} = deserialize_bit_sequences(rest, nb_sequences, sequence_size, [])

    %CrossValidate{
      address: address,
      validation_stamp: validation_stamp,
      replication_tree: replication_tree
    }
  end

  def decode(<<10::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)
    {stamp, _} = CrossValidationStamp.deserialize(rest)

    %CrossValidationDone{
      address: address,
      cross_validation_stamp: stamp
    }
  end

  def decode(<<11::8, rest::bitstring>>) do
    {tx, _} = Transaction.deserialize(rest)

    %ReplicateTransaction{
      transaction: tx
    }
  end

  def decode(<<12::8, rest::bitstring>>) do
    {address, _} = deserialize_hash(rest)

    %AcknowledgeStorage{
      address: address
    }
  end

  def decode(<<13::8, last_sync_date::32, subset::binary-size(1)>>) do
    %GetBeaconSlots{
      last_sync_date: DateTime.from_unix!(last_sync_date),
      subset: subset
    }
  end

  def decode(<<14::8, subset::8, rest::bitstring>>) do
    {node_info, _} = NodeInfo.deserialize(rest)

    %AddNodeInfo{
      subset: <<subset>>,
      node_info: node_info
    }
  end

  def decode(<<15::8, rest::bitstring>>) do
    {address, _} = deserialize_hash(rest)

    %GetLastTransaction{
      address: address
    }
  end

  def decode(<<16::8, rest::bitstring>>) do
    {address, _} = deserialize_hash(rest)

    %GetBalance{
      address: address
    }
  end

  def decode(<<17::8, rest::bitstring>>) do
    {address, _} = deserialize_hash(rest)

    %GetTransactionInputs{
      address: address
    }
  end

  def decode(<<18::8, rest::bitstring>>) do
    {address, _} = deserialize_hash(rest)

    %GetTransactionChainLength{
      address: address
    }
  end

  def decode(<<19::8, nb_node_public_keys::16, rest::binary>>) do
    {public_keys, _} = deserialize_public_key_list(rest, nb_node_public_keys, [])
    %GetP2PView{node_public_keys: public_keys}
  end

  def decode(<<20::8, rest::binary>>) do
    {address, _} = deserialize_hash(rest)
    %SubscribeTransactionValidation{address: address}
  end

  def decode(<<21::8, rest::binary>>) do
    {address, _} = deserialize_hash(rest)

    %GetFirstPublicKey{
      address: address
    }
  end

  def decode(<<242::8, rest::binary>>) do
    {public_key, _} = deserialize_public_key(rest)
    %FirstPublicKey{public_key: public_key}
  end

  def decode(<<243::8, view_size::8, rest::bitstring>>) do
    %P2PView{nodes_view: Utils.unwrap_bitstring(rest, view_size)}
  end

  def decode(<<244::8, length::16, rest::bitstring>>) do
    {inputs, _} = deserialize_transaction_inputs(rest, length, [])

    %TransactionInputList{
      inputs: inputs
    }
  end

  def decode(<<245::8, length::32>>) do
    %TransactionChainLength{
      length: length
    }
  end

  def decode(<<246::8, nb_new_seeds::8, rest::bitstring>>) do
    {new_seeds, <<nb_closest_nodes::8, rest::bitstring>>} =
      deserialize_node_list(rest, nb_new_seeds, [])

    {closest_nodes, _} = deserialize_node_list(rest, nb_closest_nodes, [])

    %BootstrappingNodes{
      new_seeds: new_seeds,
      closest_nodes: closest_nodes
    }
  end

  def decode(<<247::8, digest::binary>>) do
    %EncryptedStorageNonce{
      digest: digest
    }
  end

  def decode(<<248::8, uco_balance::float>>) do
    %Balance{
      uco: uco_balance
    }
  end

  def decode(<<249::8, nb_slots::16, rest::bitstring>>) do
    {slots, _} = deserialize_beacon_slots(rest, nb_slots, [])

    %BeaconSlotList{
      slots: slots
    }
  end

  def decode(<<250::8, nb_nodes::16, rest::bitstring>>) do
    {nodes, _} = deserialize_node_list(rest, nb_nodes, [])
    %NodeList{nodes: nodes}
  end

  def decode(<<251::8, nb_unspent_outputs::32, rest::bitstring>>) do
    {unspent_outputs, _} = deserialize_unspent_output_list(rest, nb_unspent_outputs, [])
    %UnspentOutputList{unspent_outputs: unspent_outputs}
  end

  def decode(<<252::8, nb_transactions::32, rest::bitstring>>) do
    {transactions, _} = deserialize_tx_list(rest, nb_transactions, [])
    %TransactionList{transactions: transactions}
  end

  def decode(<<253::8, rest::bitstring>>) do
    {tx, _} = Transaction.deserialize(rest)
    tx
  end

  def decode(<<254::8>>) do
    %NotFound{}
  end

  def decode(<<255::8>>) do
    %Ok{}
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

  defp deserialize_beacon_slots(rest, 0, _acc), do: {[], rest}

  defp deserialize_beacon_slots(rest, nb_slots, acc) when length(acc) == nb_slots do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_beacon_slots(rest, nb_slots, acc) do
    {slot, rest} = BeaconSlot.deserialize(rest)
    deserialize_beacon_slots(rest, nb_slots, [slot | acc])
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

  # TODO: support streaming
  @doc """
  Handle a P2P message by processing it through the dedicated context
  """
  @spec process(
          GetBootstrappingNodes.t()
          | GetStorageNonce.t()
          | ListNodes.t()
          | NewTransaction.t()
          | GetTransaction.t()
          | GetTransactionChain.t()
          | GetUnspentOutputs.t()
          | StartMining.t()
          | AddContext.t()
          | ReplicateTransaction.t()
          | AcknowledgeStorage.t()
          | CrossValidate.t()
          | CrossValidationDone.t()
          | GetBeaconSlots.t()
          | AddNodeInfo.t()
          | GetLastTransaction.t()
          | GetBalance.t()
          | GetTransactionInputs.t()
          | GetTransactionChainLength.t()
          | GetP2PView.t()
        ) ::
          Ok.t()
          | NotFound.t()
          | BootstrappingNodes.t()
          | EncryptedStorageNonce.t()
          | NodeList.t()
          | TransactionList.t()
          | Transaction.t()
          | BeaconSlotList.t()
          | Balance.t()
          | TransactionInputList.t()
          | TransactionChainLength.t()
          | UnspentOutputList.t()
          | P2PView.t()
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
        transaction: tx,
        welcome_node_public_key: welcome_node_public_key,
        validation_node_public_keys: validation_nodes
      }) do
    with true <- Mining.accept_transaction?(tx),
         true <- Mining.valid_election?(tx, validation_nodes) do
      {:ok, _} = Mining.start(tx, welcome_node_public_key, validation_nodes)
      %Ok{}
    else
      false ->
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
    case Replication.roles(tx, Crypto.node_public_key()) do
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

  def process(%GetBeaconSlots{last_sync_date: last_sync_date, subset: subset}) do
    slots = BeaconSubset.missing_slots(subset, last_sync_date)
    %BeaconSlotList{slots: slots}
  end

  def process(%AddNodeInfo{subset: subset, node_info: node_info}) do
    :ok = BeaconSubset.add_node_info(subset, node_info)
    %Ok{}
  end

  def process(%GetLastTransaction{address: address}) do
    case TransactionChain.get_last_transaction(address) do
      {:ok, tx} ->
        tx

      {:error, :transaction_not_exists} ->
        %NotFound{}
    end
  end

  def process(%GetBalance{address: address}) do
    %Balance{
      uco: Account.get_balance(address)
    }
  end

  def process(%GetTransactionInputs{address: address}) do
    %TransactionInputList{
      inputs: Account.get_inputs(address)
    }
  end

  def process(%GetTransactionChainLength{address: address}) do
    %TransactionChainLength{
      length: TransactionChain.size(address)
    }
  end

  def process(%SubscribeTransactionValidation{address: address}) do
    PubSub.register_to_new_transaction_by_address(address)

    receive do
      {:new_transaction, _} ->
        %Ok{}
    end
  end

  def process(%GetFirstPublicKey{address: address}) do
    case TransactionChain.get_first_transaction(address, [:previous_public_key]) do
      {:ok, %Transaction{previous_public_key: key}} ->
        %FirstPublicKey{public_key: key}

      {:error, :transaction_not_exists} ->
        %NotFound{}
    end
  end
end
