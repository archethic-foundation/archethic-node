defmodule ArchEthic.P2P.Message do
  @moduledoc """
  Provide functions to encode and decode P2P messages using a custom binary protocol
  """
  alias ArchEthic.Account

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.ReplicationAttestation
  alias ArchEthic.BeaconChain.Summary

  alias ArchEthic.Contracts

  alias ArchEthic.Crypto

  alias ArchEthic.Mining

  alias ArchEthic.P2P

  alias __MODULE__.AcknowledgeStorage
  alias __MODULE__.AddMiningContext
  alias __MODULE__.Balance
  alias __MODULE__.BeaconSummaryList
  alias __MODULE__.BeaconUpdate
  alias __MODULE__.BootstrappingNodes
  alias __MODULE__.CrossValidate
  alias __MODULE__.CrossValidationDone
  alias __MODULE__.EncryptedStorageNonce
  alias __MODULE__.Error
  alias __MODULE__.FirstPublicKey
  alias __MODULE__.GetBalance
  alias __MODULE__.GetBeaconSummaries
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
  alias __MODULE__.NewBeaconTransaction
  alias __MODULE__.NewTransaction
  alias __MODULE__.NodeAvailability
  alias __MODULE__.NodeList
  alias __MODULE__.NotFound
  alias __MODULE__.NotifyEndOfNodeSync
  alias __MODULE__.NotifyLastTransactionAddress
  alias __MODULE__.Ok
  alias __MODULE__.P2PView
  alias __MODULE__.Ping
  alias __MODULE__.RegisterBeaconUpdates
  alias __MODULE__.ReplicateTransaction
  alias __MODULE__.ReplicateTransactionChain
  alias __MODULE__.StartMining
  alias __MODULE__.TransactionChainLength
  alias __MODULE__.TransactionInputList
  alias __MODULE__.TransactionList
  alias __MODULE__.UnspentOutputList

  alias ArchEthic.P2P.Node

  alias ArchEthic.PubSub

  alias ArchEthic.Replication

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.CrossValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionChain.TransactionInput
  alias ArchEthic.TransactionChain.TransactionSummary

  alias ArchEthic.Utils

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
          | ReplicateTransactionChain.t()
          | GetLastTransaction.t()
          | GetBalance.t()
          | GetTransactionInputs.t()
          | GetTransactionChainLength.t()
          | NotifyEndOfNodeSync.t()
          | GetLastTransactionAddress.t()
          | NotifyLastTransactionAddress.t()
          | NodeAvailability.t()
          | Ping.t()
          | GetBeaconSummary.t()
          | NewBeaconTransaction.t()
          | GetBeaconSummaries.t()
          | RegisterBeaconUpdates.t()
          | BeaconUpdate.t()
          | TransactionSummary.t()
          | ReplicationAttestation.t()

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
          | TransactionSummary.t()
          | LastTransactionAddress.t()
          | FirstPublicKey.t()
          | TransactionChainLength.t()
          | TransactionInputList.t()
          | Error.t()
          | Summary.t()
          | BeaconSummaryList.t()

  @doc """
  Extract the Message Struct name
  """
  @spec name(t()) :: String.t()
  def name(message) when is_struct(message) do
    message.__struct__
    |> Module.split()
    |> List.last()
  end

  @doc """
  Serialize a message into binary

  ## Examples

      iex> Message.encode(%Ok{})
      <<254>>

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

  def encode(%GetTransactionChain{address: tx_address, after: nil, page: nil}) do
    <<4::8, tx_address::binary, "TIME_NIL", "PAGE_NIL">>
  end

  def encode(%GetTransactionChain{address: tx_address, after: date = %DateTime{}, page: nil}) do
    <<4::8, tx_address::binary, DateTime.to_unix(date)::32, "PAGE_NIL">>
  end

  def encode(%GetTransactionChain{address: tx_address, after: nil, page: paging_state}) do
    <<4::8, tx_address::binary, "TIME_NIL", paging_state>>
  end

  def encode(%GetTransactionChain{
        address: tx_address,
        after: date = %DateTime{},
        page: paging_state
      }) do
    <<4::8, tx_address::binary, DateTime.to_unix(date)::32, paging_state>>
  end

  def encode(%GetUnspentOutputs{address: tx_address}) do
    <<5::8, tx_address::binary>>
  end

  def encode(%NewTransaction{transaction: tx}) do
    <<6::8, Transaction.serialize(tx)::bitstring>>
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
        chain_storage_nodes_view: chain_storage_nodes_view,
        beacon_storage_nodes_view: beacon_storage_nodes_view,
        previous_storage_nodes_public_keys: previous_storage_nodes_public_keys
      }) do
    <<8::8, address::binary, validation_node_public_key::binary,
      length(previous_storage_nodes_public_keys)::8,
      :erlang.list_to_binary(previous_storage_nodes_public_keys)::binary,
      bit_size(chain_storage_nodes_view)::8, chain_storage_nodes_view::bitstring,
      bit_size(beacon_storage_nodes_view)::8, beacon_storage_nodes_view::bitstring>>
  end

  def encode(%CrossValidate{
        address: address,
        validation_stamp: stamp,
        replication_tree: %{
          chain: chain_replication_tree,
          beacon: beacon_replication_tree,
          IO: io_replication_tree
        },
        confirmed_validation_nodes: confirmed_validation_nodes
      }) do
    nb_validation_nodes = length(chain_replication_tree)
    tree_size = chain_replication_tree |> List.first() |> bit_size()

    <<9::8, address::binary, ValidationStamp.serialize(stamp)::bitstring, nb_validation_nodes::8,
      tree_size::8, :erlang.list_to_bitstring(chain_replication_tree)::bitstring,
      :erlang.list_to_bitstring(beacon_replication_tree)::bitstring,
      :erlang.list_to_bitstring(io_replication_tree)::bitstring,
      bit_size(confirmed_validation_nodes)::8, confirmed_validation_nodes::bitstring>>
  end

  def encode(%CrossValidationDone{address: address, cross_validation_stamp: stamp}) do
    <<10::8, address::binary, CrossValidationStamp.serialize(stamp)::bitstring>>
  end

  def encode(%ReplicateTransactionChain{
        transaction: tx,
        ack_storage?: ack_storage?
      }) do
    ack_storage_bit = if ack_storage?, do: 1, else: 0

    <<11::8, Transaction.serialize(tx)::bitstring, ack_storage_bit::1>>
  end

  def encode(%ReplicateTransaction{transaction: tx}) do
    <<12::8, Transaction.serialize(tx)::bitstring>>
  end

  def encode(%AcknowledgeStorage{
        signature: signature
      }) do
    <<13::8, byte_size(signature)::8, signature::binary>>
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

  def encode(%GetLastTransactionAddress{address: address, timestamp: timestamp}) do
    <<21::8, address::binary, DateTime.to_unix(timestamp)::32>>
  end

  def encode(%NotifyLastTransactionAddress{
        address: address,
        previous_address: previous_address,
        timestamp: timestamp
      }) do
    <<22::8, address::binary, previous_address::binary, DateTime.to_unix(timestamp)::32>>
  end

  def encode(%GetTransactionSummary{address: address}) do
    <<23::8, address::binary>>
  end

  def encode(%NodeAvailability{public_key: node_public_key}) do
    <<24::8, node_public_key::binary>>
  end

  def encode(%Ping{}), do: <<25::8>>

  def encode(%GetBeaconSummary{address: address}), do: <<26::8, address::binary>>

  def encode(%NewBeaconTransaction{transaction: tx}),
    do: <<27::8, Transaction.serialize(tx)::bitstring>>

  def encode(%GetBeaconSummaries{addresses: addresses}),
    do: <<28::8, length(addresses)::32, :erlang.list_to_binary(addresses)::binary>>

  def encode(%RegisterBeaconUpdates{node_public_key: node_public_key, subset: subset}) do
    <<29::8, subset::binary-size(1), node_public_key::binary>>
  end

  def encode(attestation = %ReplicationAttestation{}) do
    <<30::8, ReplicationAttestation.serialize(attestation)::binary>>
  end

  def encode(%BeaconUpdate{transaction_attestations: transaction_attestations}) do
    transaction_attestations_bin =
      transaction_attestations
      |> Enum.map(&ReplicationAttestation.serialize/1)
      |> :erlang.list_to_bitstring()

    <<236::8, length(transaction_attestations)::16, transaction_attestations_bin::bitstring>>
  end

  def encode(%BeaconSummaryList{summaries: summaries}) do
    summaries_bin =
      Stream.map(summaries, &Summary.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    <<237::8, Enum.count(summaries)::32, summaries_bin::bitstring>>
  end

  def encode(%Error{reason: reason}), do: <<238::8, Error.serialize_reason(reason)::8>>

  def encode(tx_summary = %TransactionSummary{}) do
    <<239::8, TransactionSummary.serialize(tx_summary)::binary>>
  end

  def encode(summary = %Summary{}) do
    <<240::8, Summary.serialize(summary)::bitstring>>
  end

  def encode(%LastTransactionAddress{address: address}) do
    <<241::8, address::binary>>
  end

  def encode(%FirstPublicKey{public_key: public_key}) do
    <<242::8, public_key::binary>>
  end

  def encode(%P2PView{nodes_view: view}) do
    <<243::8, bit_size(view)::8, view::bitstring>>
  end

  def encode(%TransactionInputList{inputs: inputs}) do
    inputs_bin =
      inputs
      |> Stream.map(&TransactionInput.serialize/1)
      |> Enum.to_list()
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
    <<247::8, byte_size(digest)::8, digest::binary>>
  end

  def encode(%Balance{uco: uco_balance, nft: nft_balances}) do
    nft_balances_binary =
      nft_balances
      |> Enum.reduce([], fn {nft_address, amount}, acc ->
        [<<nft_address::binary, amount::float>> | acc]
      end)
      |> Enum.reverse()
      |> :erlang.list_to_binary()

    <<248::8, uco_balance::float, map_size(nft_balances)::16, nft_balances_binary::binary>>
  end

  def encode(%NodeList{nodes: nodes}) do
    nodes_bin =
      nodes
      |> Enum.map(&Node.serialize/1)
      |> :erlang.list_to_bitstring()

    <<249::8, length(nodes)::16, nodes_bin::bitstring>>
  end

  def encode(%UnspentOutputList{unspent_outputs: unspent_outputs}) do
    unspent_outputs_bin =
      unspent_outputs
      |> Stream.map(&UnspentOutput.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_binary()

    <<250::8, Enum.count(unspent_outputs)::32, unspent_outputs_bin::binary>>
  end

  def encode(%TransactionList{transactions: transactions, page: nil}) do
    transaction_bin =
      transactions
      |> Stream.map(&Transaction.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    <<251::8, Enum.count(transactions)::32, transaction_bin::bitstring, "PAGE_NIL">>
  end

  def encode(%TransactionList{transactions: transactions, more?: true, page: paging_state}) do
    transaction_bin =
      transactions
      |> Stream.map(&Transaction.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    <<251::8, Enum.count(transactions)::32, "TRUE", transaction_bin::bitstring, paging_state>>
  end

  def encode(%TransactionList{transactions: transactions, more?: false, page: paging_state}) do
    transaction_bin =
      transactions
      |> Stream.map(&Transaction.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    <<251::8, Enum.count(transactions)::32, "FALSE", transaction_bin::bitstring, paging_state>>
  end

  def encode(tx = %Transaction{}) do
    <<252::8, Transaction.serialize(tx)::bitstring>>
  end

  def encode(%NotFound{}) do
    <<253::8>>
  end

  def encode(%Ok{}) do
    <<254::8>>
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

  def decode(<<1::8, rest::bitstring>>) do
    {public_key, rest} = Utils.deserialize_public_key(rest)

    {
      %GetStorageNonce{
        public_key: public_key
      },
      rest
    }
  end

  def decode(<<2::8, rest::bitstring>>) do
    {%ListNodes{}, rest}
  end

  def decode(<<3::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {
      %GetTransaction{address: address},
      rest
    }
  end

  #
  def decode(<<4::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    case rest do
      # both are absent and time_after and page_state
      <<"TIME_NIL", "PAGE_NIL", rest::bitstring>> ->
        {%GetTransactionChain{address: address, after: nil, page: nil}, rest}

      # time is absent
      <<"TIME_NIL", paging_state::binary()>> ->
        {%GetTransactionChain{address: address, after: nil, page: paging_state}, rest}

      # case2: page_state absent
      <<timestamp::32, "PAGE_NIL">> ->
        date = DateTime.from_unix!(timestamp)
        {%GetTransactionChain{address: address, after: date, page: nil}, rest}

      # case1-3 timestamp & page are present
      <<timestamp::32, paging_state::binary()>> ->
        date = DateTime.from_unix!(timestamp)
        {%GetTransactionChain{address: address, after: date, page: paging_state}, rest}
    end
  end

  def decode(<<5::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetUnspentOutputs{address: address}, rest}
  end

  def decode(<<6::8, rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)
    {%NewTransaction{transaction: tx}, rest}
  end

  def decode(<<7::8, rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)

    {welcome_node_public_key, <<nb_validation_nodes::8, rest::bitstring>>} =
      Utils.deserialize_public_key(rest)

    {validation_node_public_keys, rest} =
      deserialize_public_key_list(rest, nb_validation_nodes, [])

    {%StartMining{
       transaction: tx,
       welcome_node_public_key: welcome_node_public_key,
       validation_node_public_keys: validation_node_public_keys
     }, rest}
  end

  def decode(<<8::8, rest::bitstring>>) do
    {tx_address, rest} = Utils.deserialize_address(rest)

    {node_public_key, <<nb_previous_storage_nodes::8, rest::bitstring>>} =
      Utils.deserialize_public_key(rest)

    {previous_storage_nodes_keys, rest} =
      deserialize_public_key_list(rest, nb_previous_storage_nodes, [])

    <<
      chain_storage_nodes_view_size::8,
      chain_storage_nodes_view::bitstring-size(chain_storage_nodes_view_size),
      beacon_storage_nodes_view_size::8,
      beacon_storage_nodes_view::bitstring-size(beacon_storage_nodes_view_size),
      rest::bitstring
    >> = rest

    {%AddMiningContext{
       address: tx_address,
       validation_node_public_key: node_public_key,
       chain_storage_nodes_view: chain_storage_nodes_view,
       beacon_storage_nodes_view: beacon_storage_nodes_view,
       previous_storage_nodes_public_keys: previous_storage_nodes_keys
     }, rest}
  end

  def decode(<<9::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {validation_stamp, rest} = ValidationStamp.deserialize(rest)

    <<nb_validations::8, tree_size::8, rest::bitstring>> = rest

    {chain_tree, rest} = deserialize_bit_sequences(rest, nb_validations, tree_size, [])
    {beacon_tree, rest} = deserialize_bit_sequences(rest, nb_validations, tree_size, [])
    {io_tree, rest} = deserialize_bit_sequences(rest, nb_validations, tree_size, [])

    <<nb_cross_validation_nodes::8,
      cross_validation_node_confirmation::bitstring-size(nb_cross_validation_nodes),
      rest::bitstring>> = rest

    {%CrossValidate{
       address: address,
       validation_stamp: validation_stamp,
       replication_tree: %{
         chain: chain_tree,
         beacon: beacon_tree,
         IO: io_tree
       },
       confirmed_validation_nodes: cross_validation_node_confirmation
     }, rest}
  end

  def decode(<<10::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {stamp, rest} = CrossValidationStamp.deserialize(rest)

    {%CrossValidationDone{
       address: address,
       cross_validation_stamp: stamp
     }, rest}
  end

  def decode(<<11::8, rest::bitstring>>) do
    {tx, <<ack_storage_bit::1, rest::bitstring>>} = Transaction.deserialize(rest)

    ack_storage? = ack_storage_bit == 1 || false

    {%ReplicateTransactionChain{
       transaction: tx,
       ack_storage?: ack_storage?
     }, rest}
  end

  def decode(<<12::8, rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)

    {%ReplicateTransaction{
       transaction: tx
     }, rest}
  end

  def decode(
        <<13::8, signature_size::8, signature::binary-size(signature_size), rest::bitstring>>
      ) do
    {%AcknowledgeStorage{
       signature: signature
     }, rest}
  end

  def decode(<<14::8, rest::bitstring>>) do
    {public_key, <<timestamp::32, rest::bitstring>>} = Utils.deserialize_public_key(rest)

    {%NotifyEndOfNodeSync{
       node_public_key: public_key,
       timestamp: DateTime.from_unix!(timestamp)
     }, rest}
  end

  def decode(<<15::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetLastTransaction{address: address}, rest}
  end

  def decode(<<16::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetBalance{address: address}, rest}
  end

  def decode(<<17::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetTransactionInputs{address: address}, rest}
  end

  def decode(<<18::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetTransactionChainLength{address: address}, rest}
  end

  def decode(<<19::8, nb_node_public_keys::16, rest::bitstring>>) do
    {public_keys, rest} = deserialize_public_key_list(rest, nb_node_public_keys, [])
    {%GetP2PView{node_public_keys: public_keys}, rest}
  end

  def decode(<<20::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {%GetFirstPublicKey{
       address: address
     }, rest}
  end

  def decode(<<21::8, rest::bitstring>>) do
    {address, <<timestamp::32, rest::bitstring>>} = Utils.deserialize_address(rest)

    {%GetLastTransactionAddress{
       address: address,
       timestamp: DateTime.from_unix!(timestamp)
     }, rest}
  end

  def decode(<<22::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {previous_address, <<timestamp::32, rest::bitstring>>} = Utils.deserialize_address(rest)

    {%NotifyLastTransactionAddress{
       address: address,
       previous_address: previous_address,
       timestamp: DateTime.from_unix!(timestamp)
     }, rest}
  end

  def decode(<<23::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetTransactionSummary{address: address}, rest}
  end

  def decode(<<24::8, rest::binary>>) do
    {public_key, rest} = Utils.deserialize_public_key(rest)
    {%NodeAvailability{public_key: public_key}, rest}
  end

  def decode(<<25::8, rest::binary>>), do: {%Ping{}, rest}

  def decode(<<26::8, rest::binary>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {
      %GetBeaconSummary{address: address},
      rest
    }
  end

  def decode(<<27::8, rest::bitstring>>) do
    {tx = %Transaction{}, rest} = Transaction.deserialize(rest)

    {
      %NewBeaconTransaction{transaction: tx},
      rest
    }
  end

  def decode(<<28::8, nb_addresses::32, rest::bitstring>>) do
    {addresses, rest} = Utils.deserialize_addresses(rest, nb_addresses, [])

    {
      %GetBeaconSummaries{addresses: addresses},
      rest
    }
  end

  def decode(<<29::8, subset::binary-size(1), rest::binary>>) do
    {public_key, rest} = Utils.deserialize_public_key(rest)

    {
      %RegisterBeaconUpdates{
        subset: subset,
        node_public_key: public_key
      },
      rest
    }
  end

  def decode(<<30::8, rest::bitstring>>) do
    ReplicationAttestation.deserialize(rest)
  end

  def decode(<<236::8, nb_transaction_attestations::16, rest::bitstring>>) do
    {transaction_attestations, rest} =
      Utils.deserialize_transaction_attestations(rest, nb_transaction_attestations, [])

    {
      %BeaconUpdate{
        transaction_attestations: transaction_attestations
      },
      rest
    }
  end

  def decode(<<237::8, nb_summaries::32, rest::bitstring>>) do
    {summaries, rest} = deserialize_summaries(rest, nb_summaries, [])

    {
      %BeaconSummaryList{summaries: summaries},
      rest
    }
  end

  def decode(<<238::8, reason::8, rest::bitstring>>) do
    {%Error{reason: Error.deserialize_reason(reason)}, rest}
  end

  def decode(<<239::8, rest::bitstring>>) do
    TransactionSummary.deserialize(rest)
  end

  def decode(<<240::8, rest::bitstring>>) do
    Summary.deserialize(rest)
  end

  def decode(<<241::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%LastTransactionAddress{address: address}, rest}
  end

  def decode(<<242::8, rest::bitstring>>) do
    {public_key, rest} = Utils.deserialize_public_key(rest)
    {%FirstPublicKey{public_key: public_key}, rest}
  end

  def decode(<<243::8, view_size::8, rest::bitstring>>) do
    <<nodes_view::bitstring-size(view_size), rest::bitstring>> = rest
    {%P2PView{nodes_view: nodes_view}, rest}
  end

  def decode(<<244::8, nb_inputs::16, rest::bitstring>>) do
    {inputs, rest} = deserialize_transaction_inputs(rest, nb_inputs, [])

    {%TransactionInputList{
       inputs: inputs
     }, rest}
  end

  def decode(<<245::8, length::32, rest::bitstring>>) do
    {%TransactionChainLength{
       length: length
     }, rest}
  end

  def decode(<<246::8, nb_new_seeds::8, rest::bitstring>>) do
    {new_seeds, <<nb_closest_nodes::8, rest::bitstring>>} =
      deserialize_node_list(rest, nb_new_seeds, [])

    {closest_nodes, rest} = deserialize_node_list(rest, nb_closest_nodes, [])

    {%BootstrappingNodes{
       new_seeds: new_seeds,
       closest_nodes: closest_nodes
     }, rest}
  end

  def decode(<<247::8, digest_size::8, digest::binary-size(digest_size), rest::bitstring>>) do
    {%EncryptedStorageNonce{
       digest: digest
     }, rest}
  end

  def decode(<<248::8, uco_balance::float, nb_nft_balances::16, rest::bitstring>>) do
    {nft_balances, rest} = deserialize_nft_balances(rest, nb_nft_balances, %{})

    {%Balance{
       uco: uco_balance,
       nft: nft_balances
     }, rest}
  end

  def decode(<<249::8, nb_nodes::16, rest::bitstring>>) do
    {nodes, rest} = deserialize_node_list(rest, nb_nodes, [])
    {%NodeList{nodes: nodes}, rest}
  end

  def decode(<<250::8, nb_unspent_outputs::32, rest::bitstring>>) do
    {unspent_outputs, rest} = deserialize_unspent_output_list(rest, nb_unspent_outputs, [])
    {%UnspentOutputList{unspent_outputs: unspent_outputs}, rest}
  end

  def decode(<<251::8, nb_transactions::32, rest::bitstring>>) do
    {transactions, rest} = deserialize_tx_list(rest, nb_transactions, [])

    case rest do
      <<"FALSE", "PAGE_NIL">> ->
        {%TransactionList{transactions: transactions, more?: false, page: nil}, rest}

      <<"TRUE", paging_state::binary()>> ->
        {%TransactionList{transactions: transactions, more?: true, page: paging_state}, rest}

      _ ->
        {%TransactionList{transactions: transactions, more?: false, page: nil}, rest}
    end
  end

  def decode(<<252::8, rest::bitstring>>) do
    Transaction.deserialize(rest)
  end

  def decode(<<253::8, rest::bitstring>>) do
    {%NotFound{}, rest}
  end

  def decode(<<254::8, rest::bitstring>>) do
    {%Ok{}, rest}
  end

  def decode(<<255::8>>), do: raise("255 message type is reserved for stream EOF")

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
    {public_key, rest} = Utils.deserialize_public_key(rest)
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
    {nft_address, <<amount::float, rest::bitstring>>} = Utils.deserialize_address(rest)
    deserialize_nft_balances(rest, nb_nft_balances, Map.put(acc, nft_address, amount))
  end

  defp deserialize_summaries(rest, 0, _), do: {[], rest}

  defp deserialize_summaries(rest, nb_summaries, acc) when nb_summaries == length(acc),
    do: {Enum.reverse(acc), rest}

  defp deserialize_summaries(rest, nb_summaries, acc) do
    {summary, rest} = Summary.deserialize(rest)
    deserialize_summaries(rest, nb_summaries, [summary | acc])
  end

  defp deserialize_bit_sequences(rest, nb_sequences, _sequence_size, acc)
       when length(acc) == nb_sequences do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_bit_sequences(rest, nb_sequences, sequence_size, acc) do
    <<sequence::bitstring-size(sequence_size), rest::bitstring>> = rest
    deserialize_bit_sequences(rest, nb_sequences, sequence_size, [sequence | acc])
  end

  @doc """
  Handle a P2P message by processing it and return list of responses to be streamed back to the client
  """
  @spec process(request()) :: response()
  def process(%GetBootstrappingNodes{patch: patch}) do
    top_nodes = P2P.authorized_nodes()

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
    %NodeList{nodes: P2P.list_nodes()}
  end

  def process(%NewTransaction{transaction: tx}) do
    case ArchEthic.send_new_transaction(tx) do
      :ok ->
        %Ok{}

      {:error, :network_issue} ->
        %Error{reason: :network_issue}
    end
  end

  def process(%GetTransaction{address: tx_address}) do
    case TransactionChain.get_transaction(tx_address) do
      {:ok, tx} ->
        tx

      {:error, :transaction_not_exists} ->
        %NotFound{}

      {:error, :invalid_transaction} ->
        %Error{reason: :invalid_transaction}
    end
  end

  # current page state contains binary offset to resume from the query
  def process(%GetTransactionChain{
        address: tx_address,
        after: after_time,
        page: paging_state
      }) do
    {chain, more?, paging_state} =
      tx_address
      |> TransactionChain.get(after: after_time, page: paging_state)

    # new_page_state contains binary offset
    %TransactionList{transactions: chain, page: paging_state, more?: more?}
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
    if Mining.valid_election?(tx, validation_nodes) do
      {:ok, _} = Mining.start(tx, welcome_node_public_key, validation_nodes)
      %Ok{}
    else
      Logger.error("Invalid validation node election",
        transaction_address: Base.encode16(tx.address),
        transaction_type: tx.type
      )

      raise "Invalid validate node election"
    end
  end

  def process(%AddMiningContext{
        address: tx_address,
        validation_node_public_key: validation_node,
        previous_storage_nodes_public_keys: previous_storage_nodes_public_keys,
        chain_storage_nodes_view: chain_storage_nodes_view,
        beacon_storage_nodes_view: beacon_storage_nodes_view
      }) do
    :ok =
      Mining.add_mining_context(
        tx_address,
        validation_node,
        previous_storage_nodes_public_keys,
        chain_storage_nodes_view,
        beacon_storage_nodes_view
      )

    %Ok{}
  end

  def process(%ReplicateTransactionChain{
        transaction: tx,
        ack_storage?: ack_storage?
      }) do
    case Replication.validate_and_store_transaction_chain(tx, ack_storage?: ack_storage?) do
      :ok ->
        if ack_storage? do
          tx_summary = TransactionSummary.from_transaction(tx)

          %AcknowledgeStorage{
            signature: Crypto.sign_with_first_node_key(TransactionSummary.serialize(tx_summary))
          }
        else
          %Ok{}
        end

      {:error, :transaction_already_exists} ->
        %Error{reason: :transaction_already_exists}

      {:error, :invalid_transaction} ->
        %Error{reason: :invalid_transaction}
    end
  end

  def process(%ReplicateTransaction{transaction: tx}) do
    case Replication.validate_and_store_transaction(tx) do
      :ok ->
        %Ok{}

      {:error, :transaction_already_exists} ->
        %Error{reason: :transaction_already_exists}

      {:error, :invalid_transaction} ->
        %Error{reason: :invalid_transaction}
    end
  end

  def process(%CrossValidate{
        address: tx_address,
        validation_stamp: stamp,
        replication_tree: replication_tree,
        confirmed_validation_nodes: confirmed_validation_nodes
      }) do
    Mining.cross_validate(tx_address, stamp, replication_tree, confirmed_validation_nodes)
    %Ok{}
  end

  def process(%CrossValidationDone{address: tx_address, cross_validation_stamp: stamp}) do
    Mining.add_cross_validation_stamp(tx_address, stamp)
    %Ok{}
  end

  def process(%NotifyEndOfNodeSync{node_public_key: public_key, timestamp: timestamp}) do
    BeaconChain.add_end_of_node_sync(public_key, timestamp)
    %Ok{}
  end

  def process(%GetLastTransaction{address: address}) do
    case TransactionChain.get_last_transaction(address) do
      {:ok, tx} ->
        tx

      {:error, :transaction_not_exists} ->
        %NotFound{}

      {:error, :invalid_transaction} ->
        %Error{reason: :invalid_transaction}
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
    contract_inputs =
      address
      |> Contracts.list_contract_transactions()
      |> Enum.map(fn {address, timestamp} ->
        %TransactionInput{from: address, type: :call, timestamp: timestamp}
      end)

    %TransactionInputList{
      inputs: Account.get_inputs(address) ++ contract_inputs
    }
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

  def process(%GetLastTransactionAddress{address: address, timestamp: timestamp}) do
    address = TransactionChain.get_last_address(address, timestamp)
    %LastTransactionAddress{address: address}
  end

  def process(%NotifyLastTransactionAddress{
        address: address,
        previous_address: previous_address,
        timestamp: timestamp
      }) do
    Replication.acknowledge_previous_storage_nodes(address, previous_address, timestamp)
    %Ok{}
  end

  def process(%GetTransactionSummary{address: address}) do
    case TransactionChain.get_transaction_summary(address) do
      {:ok, summary} ->
        summary

      {:error, :not_found} ->
        %NotFound{}
    end
  end

  def process(%NodeAvailability{public_key: public_key}) do
    P2P.set_node_globally_available(public_key)
    %Ok{}
  end

  def process(%Ping{}), do: %Ok{}

  def process(%GetBeaconSummary{address: address}) do
    case BeaconChain.get_summary(address) do
      {:ok, summary} ->
        summary

      {:error, :not_found} ->
        %NotFound{}
    end
  end

  def process(%NewBeaconTransaction{transaction: tx}) do
    case BeaconChain.load_transaction(tx) do
      :ok ->
        %Ok{}

      :error ->
        %Error{reason: :invalid_transaction}
    end
  end

  def process(%GetBeaconSummaries{addresses: addresses}) do
    %BeaconSummaryList{
      summaries: BeaconChain.get_beacon_summaries(addresses)
    }
  end

  def process(%RegisterBeaconUpdates{node_public_key: node_public_key, subset: subset}) do
    BeaconChain.subscribe_for_beacon_updates(subset, node_public_key)
    %Ok{}
  end

  def process(%BeaconUpdate{transaction_attestations: transaction_attestations}) do
    Enum.each(transaction_attestations, &process/1)

    %Ok{}
  end

  def process(attestation = %ReplicationAttestation{}) do
    case ReplicationAttestation.validate(attestation) do
      :ok ->
        PubSub.notify_replication_attestation(attestation)
        %Ok{}

      {:error, :invalid_confirmations_signatures} ->
        %Error{reason: :invalid_attestation}
    end
  end
end
