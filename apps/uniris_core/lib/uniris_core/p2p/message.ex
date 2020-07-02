defmodule UnirisCore.P2P.Message do
  alias __MODULE__.GetBootstrappingNodes
  alias __MODULE__.GetStorageNonce
  alias __MODULE__.ListNodes
  alias __MODULE__.NewTransaction
  alias __MODULE__.GetTransaction
  alias __MODULE__.GetTransactionChain
  alias __MODULE__.GetUnspentOutputs
  alias __MODULE__.GetProofOfIntegrity
  alias __MODULE__.StartMining
  alias __MODULE__.GetTransactionHistory
  alias __MODULE__.AddContext
  alias __MODULE__.CrossValidate
  alias __MODULE__.CrossValidationDone
  alias __MODULE__.ReplicateTransaction
  alias __MODULE__.AcknowledgeStorage
  alias __MODULE__.GetBeaconSlots
  alias __MODULE__.AddNodeInfo
  alias __MODULE__.GetLastTransaction
  alias __MODULE__.GetBalance
  alias __MODULE__.GetTransactionInputs
  alias __MODULE__.BootstrappingNodes
  alias __MODULE__.ProofOfIntegrity
  alias __MODULE__.EncryptedStorageNonce
  alias __MODULE__.TransactionHistory
  alias __MODULE__.Balance
  alias __MODULE__.NodeList
  alias __MODULE__.BeaconSlotList
  alias __MODULE__.UnspentOutputList
  alias __MODULE__.TransactionList
  alias __MODULE__.Ok
  alias __MODULE__.NotFound
  alias UnirisCore.Transaction
  alias UnirisCore.Mining.Context
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias UnirisCore.Transaction.CrossValidationStamp
  alias UnirisCore.P2P.Node
  alias UnirisCore.BeaconSlot
  alias UnirisCore.BeaconSlot.NodeInfo
  alias UnirisCore.Crypto

  @type t() ::
          GetBootstrappingNodes.t()
          | GetStorageNonce.t()
          | ListNodes.t()
          | GetTransaction.t()
          | GetTransactionChain.t()
          | GetUnspentOutput.t()
          | GetProofOfIntegrity.t()
          | NewTransaction.t()
          | StartMining.t()
          | GetTransactionHistory.t()
          | AddContext.t()
          | CrossValidate.t()
          | CrossValidationDone.t()
          | ReplicateTransaction.t()
          | GetBeaconSlots.t()
          | AddNodeInfo.t()
          | GetLastTransaction.t()
          | GetBalance.t()
          | GetTransactionInputs.t()

  @doc """
  Serialize a message into binary

  ## Examples

      iex> UnirisCore.P2P.Message.encode(%Ok{})
      <<255>>

      iex> UnirisCore.P2P.Message.encode(%UnirisCore.P2P.Message.GetTransaction{
      ...>  address: <<0, 40, 71, 99, 6, 218, 243, 156, 193, 63, 176, 168, 22, 226, 31, 170, 119, 122,
      ...>    13, 188, 75, 49, 171, 219, 222, 133, 86, 132, 188, 206, 233, 66, 7>>
      ...> })
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

  def encode(%GetProofOfIntegrity{address: tx_address}) do
    <<6::8, tx_address::binary>>
  end

  def encode(%NewTransaction{transaction: tx}) do
    <<7::8, Transaction.serialize(tx)::binary>>
  end

  def encode(%StartMining{
        transaction: tx,
        welcome_node_public_key: welcome_node_public_key,
        validation_node_public_keys: validation_node_public_keys
      }) do
    <<8::8, Transaction.serialize(tx)::binary, welcome_node_public_key::binary,
      length(validation_node_public_keys)::8,
      :erlang.list_to_binary(validation_node_public_keys)::binary>>
  end

  def encode(%GetTransactionHistory{address: address}) do
    <<9::8, address::binary>>
  end

  def encode(%AddContext{
        address: address,
        validation_node_public_key: validation_node,
        context: %Context{
          involved_nodes: involved_node_public_keys,
          cross_validation_nodes_view: cross_validation_nodes_view,
          chain_storage_nodes_view: chain_storage_nodes_view,
          beacon_storage_nodes_view: beacon_storage_nodes_view
        }
      }) do
    <<10::8, address::binary, validation_node::binary, length(involved_node_public_keys)::8,
      :erlang.list_to_binary(involved_node_public_keys)::binary,
      bit_size(cross_validation_nodes_view)::8, cross_validation_nodes_view::bitstring,
      bit_size(chain_storage_nodes_view)::8, chain_storage_nodes_view::bitstring,
      bit_size(beacon_storage_nodes_view)::8, beacon_storage_nodes_view::bitstring>>
  end

  def encode(%CrossValidate{
        address: address,
        validation_stamp: stamp,
        replication_tree: replication_tree
      }) do
    <<11::8, address::binary, ValidationStamp.serialize(stamp)::binary,
      length(replication_tree)::8, bit_size(List.first(replication_tree)),
      :erlang.list_to_bitstring(replication_tree)::bitstring>>
  end

  def encode(%CrossValidationDone{address: address, cross_validation_stamp: stamp}) do
    <<12::8, address::binary, CrossValidationStamp.serialize(stamp)::binary>>
  end

  def encode(%ReplicateTransaction{transaction: tx}) do
    <<13::8, Transaction.serialize(tx)::binary>>
  end

  def encode(%AcknowledgeStorage{address: address}) do
    <<14::8, address::binary>>
  end

  def encode(%GetBeaconSlots{subsets_slots: subsets_slots}) do
    nb_subsets = map_size(subsets_slots)

    subset_slots_bin =
      subsets_slots
      |> Enum.map(fn {subset, slot_times} ->
        [
          subset,
          <<length(slot_times)::16>>,
          Enum.map(slot_times, fn date -> <<DateTime.to_unix(date)::32>> end)
        ]
        |> :erlang.list_to_binary()
      end)
      |> :erlang.list_to_binary()

    <<15::8, nb_subsets::8, subset_slots_bin::binary>>
  end

  def encode(%AddNodeInfo{subset: subset, node_info: node_info}) do
    <<16::8, subset::binary, NodeInfo.serialize(node_info)::bitstring>>
  end

  def encode(%GetLastTransaction{address: address}) do
    <<17::8, address::binary>>
  end

  def encode(%GetBalance{address: address}) do
    <<18::8, address::binary>>
  end

  def encode(%GetTransactionInputs{address: address}) do
    <<19::8, address::binary>>
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

    <<244::8, length(new_seeds)::8, new_seeds_bin::bitstring, length(closest_nodes)::8,
      closest_nodes_bin::bitstring>>
  end

  def encode(%ProofOfIntegrity{digest: digest}) do
    <<245::8, digest::binary>>
  end

  def encode(%EncryptedStorageNonce{digest: digest}) do
    <<246::8, digest::binary>>
  end

  def encode(%Balance{uco: uco_balance}) do
    <<247::8, uco_balance::float>>
  end

  def encode(%TransactionHistory{transaction_chain: chain, unspent_outputs: utxos}) do
    chain_bin =
      chain
      |> Enum.map(&Transaction.serialize/1)
      |> :erlang.list_to_binary()

    utxo_bin =
      utxos
      |> Enum.map(&UnspentOutput.serialize/1)
      |> :erlang.list_to_binary()

    <<248::8, length(chain)::32, chain_bin::binary, length(utxos)::32, utxo_bin::binary>>
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
    uxto_bin =
      unspent_outputs
      |> Enum.map(&UnspentOutput.serialize/1)
      |> :erlang.list_to_binary()

    <<251::8, length(unspent_outputs)::32, uxto_bin::binary>>
  end

  def encode(%TransactionList{transactions: transactions}) do
    transaction_bin =
      transactions
      |> Enum.map(&Transaction.serialize/1)
      |> :erlang.list_to_binary()

    <<252::8, length(transactions)::32, transaction_bin::binary>>
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
    {address, _} = deserialize_hash(rest)

    %GetProofOfIntegrity{
      address: address
    }
  end

  def decode(<<7::8, rest::bitstring>>) do
    {tx, _} = Transaction.deserialize(rest)

    %NewTransaction{
      transaction: tx
    }
  end

  def decode(<<8::8, rest::bitstring>>) do
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

  def decode(<<9::8, rest::bitstring>>) do
    {address, _} = deserialize_hash(rest)

    %GetTransactionHistory{
      address: address
    }
  end

  def decode(<<10::8, hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<address::binary-size(hash_size), curve_id::8, rest::bitstring>> = rest
    key_size = Crypto.key_size(curve_id)
    <<key::binary-size(key_size), nb_involved_nodes::8, rest::bitstring>> = rest

    {involved_nodes, rest} = deserialize_public_key_list(rest, nb_involved_nodes, [])

    <<cross_validation_nodes_view_size::8,
      cross_validation_nodes_view::bitstring-size(cross_validation_nodes_view_size),
      chain_storage_nodes_view_size::8,
      chain_storage_nodes_view::bitstring-size(chain_storage_nodes_view_size),
      beacon_storage_nodes_view_size::8,
      beacon_storage_nodes_view::bitstring-size(beacon_storage_nodes_view_size),
      _::bitstring>> = rest

    %AddContext{
      address: <<hash_id::8, address::binary>>,
      validation_node_public_key: <<curve_id::8, key::binary>>,
      context: %Context{
        involved_nodes: involved_nodes,
        cross_validation_nodes_view: cross_validation_nodes_view,
        chain_storage_nodes_view: chain_storage_nodes_view,
        beacon_storage_nodes_view: beacon_storage_nodes_view
      }
    }
  end

  def decode(<<11::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)
    {validation_stamp, rest} = ValidationStamp.deserialize(rest)

    <<nb_sequences::8, sequence_size::8, rest::bitstring>> = rest
    {replication_tree, _} = deserialize_bitsequences(rest, nb_sequences, sequence_size, [])

    %CrossValidate{
      address: address,
      validation_stamp: validation_stamp,
      replication_tree: replication_tree
    }
  end

  def decode(<<12::8, rest::bitstring>>) do
    {address, rest} = deserialize_hash(rest)
    {stamp, _} = CrossValidationStamp.deserialize(rest)

    %CrossValidationDone{
      address: address,
      cross_validation_stamp: stamp
    }
  end

  def decode(<<13::8, rest::bitstring>>) do
    {tx, _} = Transaction.deserialize(rest)

    %ReplicateTransaction{
      transaction: tx
    }
  end

  def decode(<<14::8, rest::bitstring>>) do
    {address, _} = deserialize_hash(rest)

    %AcknowledgeStorage{
      address: address
    }
  end

  def decode(<<15::8, nb_subsets::8, rest::bitstring>>) do
    {subset_slots, _} = deserialize_beacon_subset_slot_times(rest, nb_subsets, [])

    %GetBeaconSlots{
      subsets_slots: subset_slots
    }
  end

  def decode(<<16::8, subset::8, rest::bitstring>>) do
    {node_info, _} = NodeInfo.deserialize(rest)

    %AddNodeInfo{
      subset: <<subset>>,
      node_info: node_info
    }
  end

  def decode(<<17::8, rest::bitstring>>) do
    {address, _} = deserialize_hash(rest)

    %GetLastTransaction{
      address: address
    }
  end

  def decode(<<18::8, rest::bitstring>>) do
    {address, _} = deserialize_hash(rest)

    %GetBalance{
      address: address
    }
  end

  def decode(<<19::8, rest::bitstring>>) do
    {address, _} = deserialize_hash(rest)

    %GetTransactionInputs{
      address: address
    }
  end

  def decode(<<244::8, nb_new_seeds::8, rest::bitstring>>) do
    {new_seeds, <<nb_closest_nodes::8, rest::bitstring>>} =
      deserialize_node_list(rest, nb_new_seeds, [])

    {closest_nodes, _} = deserialize_node_list(rest, nb_closest_nodes, [])

    %BootstrappingNodes{
      new_seeds: new_seeds,
      closest_nodes: closest_nodes
    }
  end

  def decode(<<245::8, rest::bitstring>>) do
    {hash, _} = deserialize_hash(rest)

    %ProofOfIntegrity{
      digest: hash
    }
  end

  def decode(<<246::8, digest::binary>>) do
    %EncryptedStorageNonce{
      digest: digest
    }
  end

  def decode(<<247::8, uco_balance::float>>) do
    %Balance{
      uco: uco_balance
    }
  end

  def decode(<<248::8, nb_transactions::32, rest::bitstring>>) do
    {transactions, <<nb_utxos::32, rest::bitstring>>} =
      deserialize_tx_list(rest, nb_transactions, [])

    {utxos, _} = deserialize_utxo_list(rest, nb_utxos, [])

    %TransactionHistory{
      transaction_chain: transactions,
      unspent_outputs: utxos
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

  def decode(<<251::8, nb_utxos::32, rest::bitstring>>) do
    {utxos, _} = deserialize_utxo_list(rest, nb_utxos, [])
    %UnspentOutputList{unspent_outputs: utxos}
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

  defp deserialize_utxo_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_utxo_list(rest, nb_utxo, acc) when length(acc) == nb_utxo do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_utxo_list(rest, nb_utxo, acc) do
    {utxo, rest} = UnspentOutput.deserialize(rest)
    deserialize_utxo_list(rest, nb_utxo, [utxo | acc])
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

  defp deserialize_bitsequences(rest, nb_sequences, _sequence_size, acc)
       when length(acc) == nb_sequences do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_bitsequences(rest, nb_sequences, sequence_size, acc) do
    <<sequence::bitstring-size(sequence_size), rest::bitstring>> = rest
    deserialize_bitsequences(rest, nb_sequences, sequence_size, [sequence | acc])
  end

  defp deserialize_beacon_subset_slot_times(rest, 0, _acc), do: {[], rest}

  defp deserialize_beacon_subset_slot_times(rest, nb_subsets, acc)
       when length(acc) == nb_subsets do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_beacon_subset_slot_times(
         <<subset::8, nb_slot_times::16, rest::bitstring>>,
         nb_subsets,
         acc
       ) do
    {slot_times, rest} = deserialize_timestamps(rest, nb_slot_times, [])
    deserialize_beacon_subset_slot_times(rest, nb_subsets, [%{<<subset>> => slot_times} | acc])
  end

  defp deserialize_timestamps(rest, 0, _acc), do: {[], rest}

  defp deserialize_timestamps(rest, nb_timestamps, acc) when length(acc) == nb_timestamps do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_timestamps(rest, nb_timestamps, acc) do
    <<timestamp::32, rest::binary>> = rest
    deserialize_timestamps(rest, nb_timestamps, [DateTime.from_unix!(timestamp) | acc])
  end

  @doc """
  Wrap any bitstring which is not byte even by padding the remaining bits to make an even binary

  ## Examples

      iex> UnirisCore.P2P.Message.wrap_binary(<<1::1>>)
      <<1::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1>>

      iex> UnirisCore.P2P.Message.wrap_binary(<<33, 50, 10>>)
      <<33, 50, 10>>
  """
  @spec wrap_binary(bitstring()) :: binary()
  def wrap_binary(bits) when is_bitstring(bits) do
    size = bit_size(bits)

    if rem(size, 8) == 0 do
      bits
    else
      # Find out the next greate multiple of 8
      round_up = Bitwise.band(size + 7, -8)
      pad_bitstring(bits, round_up - size)
    end
  end

  defp pad_bitstring(original_bits, additional_bits) do
    <<original_bits::bitstring, 0::size(additional_bits)>>
  end
end
