defmodule Archethic.P2P.Message do
  @moduledoc """
  Provide functions to encode and decode P2P messages using a custom binary protocol
  """

  alias Archethic.{
    Account,
    BeaconChain,
    Contracts,
    Crypto,
    Election,
    Mining,
    P2P,
    P2P.Node,
    PubSub,
    Replication,
    TransactionChain,
    TaskSupervisor,
    Utils,
    Utils.VarInt
  }

  alias ArchethicWeb.TransactionSubscriber

  alias Archethic.BeaconChain.{
    ReplicationAttestation,
    Summary,
    SummaryAggregate,
    Slot,
    Subset,
    Slot
  }

  alias Archethic.TransactionChain.{
    Transaction,
    Transaction.CrossValidationStamp,
    Transaction.ValidationStamp,
    TransactionInput,
    TransactionSummary,
    VersionedTransactionInput,
    Transaction.ValidationStamp.LedgerOperations,
    Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput
  }

  alias __MODULE__.{
    AcknowledgeStorage,
    AddMiningContext,
    Balance,
    BeaconSummaryList,
    BeaconUpdate,
    BootstrappingNodes,
    CrossValidate,
    CrossValidationDone,
    EncryptedStorageNonce,
    Error,
    FirstPublicKey,
    FirstAddress,
    GetFirstAddress,
    GetBalance,
    GetBeaconSummaries,
    GetBeaconSummary,
    GetBeaconSummariesAggregate,
    GetBootstrappingNodes,
    GetCurrentSummaries,
    GetFirstPublicKey,
    GetLastTransaction,
    GetLastTransactionAddress,
    GetP2PView,
    GetStorageNonce,
    GetTransaction,
    GetTransactionChain,
    GetTransactionChainLength,
    GetTransactionInputs,
    GetTransactionSummary,
    GetUnspentOutputs,
    LastTransactionAddress,
    ListNodes,
    NewBeaconSlot,
    NewTransaction,
    NodeList,
    NotFound,
    NotifyEndOfNodeSync,
    NotifyLastTransactionAddress,
    NotifyPreviousChain,
    Ok,
    P2PView,
    Ping,
    RegisterBeaconUpdates,
    ReplicateTransaction,
    ReplicateTransactionChain,
    ReplicationError,
    ShardRepair,
    StartMining,
    TransactionChainLength,
    TransactionInputList,
    TransactionSummaryList,
    TransactionList,
    UnspentOutputList,
    ValidationError
  }

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
          | Ping.t()
          | GetBeaconSummary.t()
          | NewBeaconSlot.t()
          | GetBeaconSummaries.t()
          | RegisterBeaconUpdates.t()
          | BeaconUpdate.t()
          | TransactionSummary.t()
          | ReplicationAttestation.t()
          | GetFirstAddress.t()
          | ValidationError.t()
          | GetCurrentSummaries.t()
          | GetBeaconSummariesAggregate.t()
          | NotifyPreviousChain.t()
          | ShardRepair.t()

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
          | TransactionSummary.t()
          | LastTransactionAddress.t()
          | FirstPublicKey.t()
          | TransactionChainLength.t()
          | TransactionInputList.t()
          | TransactionSummaryList.t()
          | Error.t()
          | Summary.t()
          | BeaconSummaryList.t()
          | FirstAddress.t()
          | ReplicationError.t()
          | SummaryAggregate.t()

  @floor_upload_speed Application.compile_env!(:archethic, [__MODULE__, :floor_upload_speed])
  @content_max_size Application.compile_env!(:archethic, :transaction_data_content_max_size)

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
  Return timeout depending of message type
  """
  @spec get_timeout(__MODULE__.t()) :: non_neg_integer()
  def get_timeout(%GetTransaction{}), do: get_max_timeout()
  def get_timeout(%GetLastTransaction{}), do: get_max_timeout()
  def get_timeout(%NewTransaction{}), do: get_max_timeout()
  def get_timeout(%StartMining{}), do: get_max_timeout()
  def get_timeout(%ReplicateTransaction{}), do: get_max_timeout()
  def get_timeout(%ReplicateTransactionChain{}), do: get_max_timeout()

  def get_timeout(%GetTransactionChain{}) do
    # As we use 10 transaction in the pagination we can estimate the max time
    get_max_timeout() * 10
  end

  #  def get_timeout(%GetBeaconSummaries{addresses: addresses}) do
  #    # We can expect high beacon summary where a transaction replication will contains a single UCO transfer
  #    # CALC: Tx address +  recipient address + tx type + tx timestamp + storage node public key + signature * 200 (max storage nodes)
  #    beacon_summary_high_estimation_bytes = 34 + 34 + 1 + 8 + (8 + 34 + 34 * 200)
  #    length(addresses) * trunc(beacon_summary_high_estimation_bytes / @floor_upload_speed * 1000)
  #  end

  def get_timeout(_), do: 3_000

  @doc """
  Return the maximum timeout for a full sized transaction
  """
  @spec get_max_timeout() :: non_neg_integer()
  def get_max_timeout() do
    trunc(@content_max_size / @floor_upload_speed * 1_000)
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

  def encode(%GetTransactionChain{address: tx_address, paging_state: nil}) do
    <<4::8, tx_address::binary, 0::8>>
  end

  def encode(%GetTransactionChain{address: tx_address, paging_state: paging_state}) do
    <<4::8, tx_address::binary, byte_size(paging_state)::8, paging_state::binary>>
  end

  def encode(%GetUnspentOutputs{address: tx_address, offset: offset}) do
    <<5::8, tx_address::binary, VarInt.from_value(offset)::binary>>
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
        io_storage_nodes_view: io_storage_nodes_view,
        previous_storage_nodes_public_keys: previous_storage_nodes_public_keys
      }) do
    <<8::8, address::binary, validation_node_public_key::binary,
      length(previous_storage_nodes_public_keys)::8,
      :erlang.list_to_binary(previous_storage_nodes_public_keys)::binary,
      bit_size(chain_storage_nodes_view)::8, chain_storage_nodes_view::bitstring,
      bit_size(beacon_storage_nodes_view)::8, beacon_storage_nodes_view::bitstring,
      bit_size(io_storage_nodes_view)::8, io_storage_nodes_view::bitstring>>
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
    chain_tree_size = chain_replication_tree |> List.first() |> bit_size()
    beacon_tree_size = beacon_replication_tree |> List.first() |> bit_size()

    io_tree_size =
      case io_replication_tree do
        [] ->
          0

        tree ->
          tree
          |> List.first()
          |> bit_size()
      end

    <<9::8, address::binary, ValidationStamp.serialize(stamp)::bitstring, nb_validation_nodes::8,
      chain_tree_size::8, :erlang.list_to_bitstring(chain_replication_tree)::bitstring,
      beacon_tree_size::8, :erlang.list_to_bitstring(beacon_replication_tree)::bitstring,
      io_tree_size::8, :erlang.list_to_bitstring(io_replication_tree)::bitstring,
      bit_size(confirmed_validation_nodes)::8, confirmed_validation_nodes::bitstring>>
  end

  def encode(%CrossValidationDone{address: address, cross_validation_stamp: stamp}) do
    <<10::8, address::binary, CrossValidationStamp.serialize(stamp)::bitstring>>
  end

  def encode(%ReplicateTransactionChain{transaction: tx, replying_node: nil}) do
    <<11::8, Transaction.serialize(tx)::bitstring, 0::1>>
  end

  def encode(%ReplicateTransactionChain{transaction: tx, replying_node: replying_node_public_key}) do
    <<11::8, Transaction.serialize(tx)::bitstring, 1::1, replying_node_public_key::binary>>
  end

  def encode(%ReplicateTransaction{transaction: tx}) do
    <<12::8, Transaction.serialize(tx)::bitstring>>
  end

  def encode(%AcknowledgeStorage{
        address: address,
        signature: signature,
        node_public_key: node_public_key
      }) do
    <<13::8, address::binary, node_public_key::binary, byte_size(signature)::8,
      signature::binary>>
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

  def encode(%GetTransactionInputs{address: address, offset: offset, limit: limit}) do
    <<17::8, address::binary, VarInt.from_value(offset)::binary,
      VarInt.from_value(limit)::binary>>
  end

  def encode(%GetTransactionChainLength{address: address}) do
    <<18::8, address::binary>>
  end

  def encode(%GetP2PView{node_public_keys: node_public_keys}) do
    encoded_node_public_keys_length = length(node_public_keys) |> VarInt.from_value()

    <<19::8, encoded_node_public_keys_length::binary,
      :erlang.list_to_binary(node_public_keys)::binary>>
  end

  def encode(%GetFirstPublicKey{public_key: public_key}) do
    <<20::8, public_key::binary>>
  end

  def encode(%GetLastTransactionAddress{address: address, timestamp: timestamp}) do
    <<21::8, address::binary, DateTime.to_unix(timestamp, :millisecond)::64>>
  end

  def encode(%NotifyLastTransactionAddress{
        last_address: last_address,
        genesis_address: genesis_address,
        timestamp: timestamp
      }) do
    <<22::8, last_address::binary, genesis_address::binary,
      DateTime.to_unix(timestamp, :millisecond)::64>>
  end

  def encode(%GetTransactionSummary{address: address}) do
    <<23::8, address::binary>>
  end

  def encode(%Ping{}), do: <<25::8>>

  def encode(%GetBeaconSummary{address: address}), do: <<26::8, address::binary>>

  def encode(%NewBeaconSlot{slot: slot}),
    do: <<27::8, Slot.serialize(slot) |> Utils.wrap_binary()::bitstring>>

  def encode(%GetBeaconSummaries{addresses: addresses}) do
    encoded_addresses_length = length(addresses) |> VarInt.from_value()
    <<28::8, encoded_addresses_length::binary, :erlang.list_to_binary(addresses)::binary>>
  end

  def encode(%RegisterBeaconUpdates{node_public_key: node_public_key, subset: subset}) do
    <<29::8, subset::binary-size(1), node_public_key::binary>>
  end

  def encode(attestation = %ReplicationAttestation{}) do
    <<30::8, ReplicationAttestation.serialize(attestation)::binary>>
  end

  def encode(%GetFirstAddress{address: address}) do
    <<31::8, address::binary>>
  end

  def encode(%GetCurrentSummaries{subsets: subsets}) do
    subsets_bin = :erlang.list_to_binary(subsets)
    <<32::8, length(subsets)::8, subsets_bin::binary>>
  end

  def encode(%GetBeaconSummariesAggregate{date: date}) do
    <<33::8, DateTime.to_unix(date)::32>>
  end

  def encode(%NotifyPreviousChain{address: address}) do
    <<34::8, address::binary>>
  end

  def encode(msg = %ShardRepair{}) do
    <<230::8, ShardRepair.serialize(msg)::bitstring>>
  end

  def encode(aggregate = %SummaryAggregate{}) do
    <<231::8, SummaryAggregate.serialize(aggregate)::bitstring>>
  end

  def encode(%TransactionSummaryList{transaction_summaries: transaction_summaries}) do
    transaction_summaries_bin =
      transaction_summaries
      |> Enum.map(&TransactionSummary.serialize/1)
      |> :erlang.list_to_bitstring()

    encoded_transaction_summaries_len = length(transaction_summaries) |> VarInt.from_value()

    <<232::8, encoded_transaction_summaries_len::binary, transaction_summaries_bin::bitstring>>
  end

  def encode(%ReplicationError{address: address, reason: reason}) do
    <<233::8, address::binary, ReplicationError.serialize_reason(reason)::8>>
  end

  def encode(%ValidationError{context: :network_issue, reason: reason, address: address}) do
    <<234::8, address::binary, reason |> byte_size() |> VarInt.from_value()::binary,
      reason::binary, 0::8>>
  end

  def encode(%ValidationError{context: :invalid_transaction, reason: reason, address: address}) do
    <<234::8, address::binary, reason |> byte_size() |> VarInt.from_value()::binary,
      reason::binary, 1::8>>
  end

  def encode(%FirstAddress{address: address}) do
    <<235::8, address::binary>>
  end

  def encode(%BeaconUpdate{transaction_attestations: transaction_attestations}) do
    transaction_attestations_bin =
      transaction_attestations
      |> Enum.map(&ReplicationAttestation.serialize/1)
      |> :erlang.list_to_bitstring()

    encoded_transaction_attestations_len = length(transaction_attestations) |> VarInt.from_value()

    <<236::8, encoded_transaction_attestations_len::binary,
      transaction_attestations_bin::bitstring>>
  end

  def encode(%BeaconSummaryList{summaries: summaries}) do
    summaries_bin =
      Stream.map(summaries, &Summary.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_summaries_length = Enum.count(summaries) |> VarInt.from_value()

    <<237::8, encoded_summaries_length::binary, summaries_bin::bitstring>>
  end

  def encode(%Error{reason: reason}), do: <<238::8, Error.serialize_reason(reason)::8>>

  def encode(tx_summary = %TransactionSummary{}) do
    <<239::8, TransactionSummary.serialize(tx_summary)::binary>>
  end

  def encode(summary = %Summary{}) do
    <<240::8, Summary.serialize(summary)::bitstring>>
  end

  def encode(%LastTransactionAddress{address: address, timestamp: timestamp}) do
    <<241::8, address::binary, DateTime.to_unix(timestamp, :millisecond)::64>>
  end

  def encode(%FirstPublicKey{public_key: public_key}) do
    <<242::8, public_key::binary>>
  end

  def encode(%P2PView{nodes_view: view}) do
    <<243::8, bit_size(view)::8, view::bitstring>>
  end

  def encode(%TransactionInputList{inputs: inputs, more?: more?, offset: offset}) do
    inputs_bin =
      inputs
      |> Stream.map(&VersionedTransactionInput.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_inputs_length = length(inputs) |> VarInt.from_value()

    more_bit = if more?, do: 1, else: 0

    <<244::8, encoded_inputs_length::binary, inputs_bin::bitstring, more_bit::1,
      VarInt.from_value(offset)::binary>>
  end

  def encode(%TransactionChainLength{length: length}) do
    encoded_length = length |> VarInt.from_value()
    <<245::8, encoded_length::binary>>
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

    encoded_new_seeds_length = length(new_seeds) |> VarInt.from_value()

    encoded_closest_nodes_length = length(closest_nodes) |> VarInt.from_value()

    <<246::8, encoded_new_seeds_length::binary, new_seeds_bin::bitstring,
      encoded_closest_nodes_length::binary, closest_nodes_bin::bitstring>>
  end

  def encode(%EncryptedStorageNonce{digest: digest}) do
    <<247::8, byte_size(digest)::8, digest::binary>>
  end

  def encode(%Balance{uco: uco_balance, token: token_balances}) do
    token_balances_binary =
      token_balances
      |> Enum.reduce([], fn {{token_address, token_id}, amount}, acc ->
        [<<token_address::binary, amount::64, VarInt.from_value(token_id)::binary>> | acc]
      end)
      |> Enum.reverse()
      |> :erlang.list_to_binary()

    encoded_token_balances_length = map_size(token_balances) |> VarInt.from_value()

    <<248::8, uco_balance::64, encoded_token_balances_length::binary,
      token_balances_binary::binary>>
  end

  def encode(%NodeList{nodes: nodes}) do
    nodes_bin =
      nodes
      |> Enum.map(&Node.serialize/1)
      |> :erlang.list_to_bitstring()

    encoded_nodes_length = length(nodes) |> VarInt.from_value()

    <<249::8, encoded_nodes_length::binary, nodes_bin::bitstring>>
  end

  def encode(%UnspentOutputList{unspent_outputs: unspent_outputs, more?: more?, offset: offset}) do
    unspent_outputs_bin =
      unspent_outputs
      |> Stream.map(&VersionedUnspentOutput.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_binary()

    encoded_unspent_outputs_length =
      unspent_outputs
      |> Enum.count()
      |> VarInt.from_value()

    more_bit = if more?, do: 1, else: 0

    <<250::8, encoded_unspent_outputs_length::binary, unspent_outputs_bin::binary, more_bit::1,
      VarInt.from_value(offset)::binary>>
  end

  def encode(%TransactionList{transactions: transactions, more?: false}) do
    transaction_bin =
      transactions
      |> Stream.map(&Transaction.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_transactions_length = Enum.count(transactions) |> VarInt.from_value()

    <<251::8, encoded_transactions_length::binary, transaction_bin::bitstring, 0::1>>
  end

  def encode(%TransactionList{transactions: transactions, more?: true, paging_state: paging_state}) do
    transaction_bin =
      transactions
      |> Stream.map(&Transaction.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_transactions_length = Enum.count(transactions) |> VarInt.from_value()

    <<251::8, encoded_transactions_length::binary, transaction_bin::bitstring, 1::1,
      byte_size(paging_state)::8, paging_state::binary>>
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
    {address,
     <<paging_state_size::8, paging_state::binary-size(paging_state_size), rest::bitstring>>} =
      Utils.deserialize_address(rest)

    paging_state =
      case paging_state do
        "" ->
          nil

        _ ->
          paging_state
      end

    {
      %GetTransactionChain{address: address, paging_state: paging_state},
      rest
    }
  end

  def decode(<<5::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {offset, rest} = VarInt.get_value(rest)
    {%GetUnspentOutputs{address: address, offset: offset}, rest}
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
      Utils.deserialize_public_key_list(rest, nb_validation_nodes, [])

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
      Utils.deserialize_public_key_list(rest, nb_previous_storage_nodes, [])

    <<
      chain_storage_nodes_view_size::8,
      chain_storage_nodes_view::bitstring-size(chain_storage_nodes_view_size),
      beacon_storage_nodes_view_size::8,
      beacon_storage_nodes_view::bitstring-size(beacon_storage_nodes_view_size),
      io_storage_nodes_view_size::8,
      io_storage_nodes_view::bitstring-size(io_storage_nodes_view_size),
      rest::bitstring
    >> = rest

    {%AddMiningContext{
       address: tx_address,
       validation_node_public_key: node_public_key,
       chain_storage_nodes_view: chain_storage_nodes_view,
       beacon_storage_nodes_view: beacon_storage_nodes_view,
       io_storage_nodes_view: io_storage_nodes_view,
       previous_storage_nodes_public_keys: previous_storage_nodes_keys
     }, rest}
  end

  def decode(<<9::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {validation_stamp, <<nb_validations::8, rest::bitstring>>} = ValidationStamp.deserialize(rest)

    <<chain_tree_size::8, rest::bitstring>> = rest

    {chain_tree, <<beacon_tree_size::8, rest::bitstring>>} =
      deserialize_bit_sequences(rest, nb_validations, chain_tree_size, [])

    {beacon_tree, <<io_tree_size::8, rest::bitstring>>} =
      deserialize_bit_sequences(rest, nb_validations, beacon_tree_size, [])

    {io_tree, rest} =
      if io_tree_size > 0 do
        deserialize_bit_sequences(rest, nb_validations, io_tree_size, [])
      else
        {[], rest}
      end

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
    {tx, <<replying_node::1, rest::bitstring>>} = Transaction.deserialize(rest)

    if replying_node == 1 do
      {node_public_key, rest} = Utils.deserialize_public_key(rest)

      {%ReplicateTransactionChain{
         transaction: tx,
         replying_node: node_public_key
       }, rest}
    else
      {%ReplicateTransactionChain{
         transaction: tx
       }, rest}
    end
  end

  def decode(<<12::8, rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)

    {%ReplicateTransaction{
       transaction: tx
     }, rest}
  end

  def decode(<<13::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {public_key, <<signature_size::8, signature::binary-size(signature_size), rest::bitstring>>} =
      Utils.deserialize_public_key(rest)

    {%AcknowledgeStorage{
       address: address,
       signature: signature,
       node_public_key: public_key
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
    {offset, rest} = VarInt.get_value(rest)
    {limit, rest} = VarInt.get_value(rest)
    {%GetTransactionInputs{address: address, offset: offset, limit: limit}, rest}
  end

  def decode(<<18::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetTransactionChainLength{address: address}, rest}
  end

  def decode(<<19::8, rest::bitstring>>) do
    {nb_node_public_keys, rest} = rest |> VarInt.get_value()
    {public_keys, rest} = Utils.deserialize_public_key_list(rest, nb_node_public_keys, [])
    {%GetP2PView{node_public_keys: public_keys}, rest}
  end

  def decode(<<20::8, rest::bitstring>>) do
    {public_key, rest} = Utils.deserialize_public_key(rest)

    {%GetFirstPublicKey{
       public_key: public_key
     }, rest}
  end

  def decode(<<21::8, rest::bitstring>>) do
    {address, <<timestamp::64, rest::bitstring>>} = Utils.deserialize_address(rest)

    {%GetLastTransactionAddress{
       address: address,
       timestamp: DateTime.from_unix!(timestamp, :millisecond)
     }, rest}
  end

  def decode(<<22::8, rest::bitstring>>) do
    {last_address, rest} = Utils.deserialize_address(rest)
    {genesis_address, <<timestamp::64, rest::bitstring>>} = Utils.deserialize_address(rest)

    {%NotifyLastTransactionAddress{
       last_address: last_address,
       genesis_address: genesis_address,
       timestamp: DateTime.from_unix!(timestamp, :millisecond)
     }, rest}
  end

  def decode(<<23::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetTransactionSummary{address: address}, rest}
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
    {slot = %Slot{}, rest} = Slot.deserialize(rest)

    {
      %NewBeaconSlot{slot: slot},
      rest
    }
  end

  def decode(<<28::8, rest::bitstring>>) do
    {nb_addresses, rest} = rest |> VarInt.get_value()
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

  def decode(<<31::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetFirstAddress{address: address}, rest}
  end

  def decode(<<32::8, nb_subsets::8, rest::binary>>) do
    subsets_bin = :binary.part(rest, 0, nb_subsets)
    subsets = for <<subset::8 <- subsets_bin>>, do: <<subset>>
    {%GetCurrentSummaries{subsets: subsets}, <<>>}
  end

  def decode(<<33::8, timestamp::32, rest::bitstring>>) do
    {%GetBeaconSummariesAggregate{date: DateTime.from_unix!(timestamp)}, rest}
  end

  def decode(<<34::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%NotifyPreviousChain{address: address}, rest}
  end

  def decode(<<230::8, rest::bitstring>>) do
    ShardRepair.deserialize(rest)
  end

  def decode(<<231::8, rest::bitstring>>) do
    SummaryAggregate.deserialize(rest)
  end

  def decode(<<232::8, rest::bitstring>>) do
    {nb_transaction_summaries, rest} = rest |> VarInt.get_value()

    {transaction_summaries, rest} =
      Utils.deserialize_transaction_summaries(rest, nb_transaction_summaries, [])

    {
      %TransactionSummaryList{
        transaction_summaries: transaction_summaries
      },
      rest
    }
  end

  def decode(<<233::8, rest::bitstring>>) do
    {address, <<reason::8, rest::bitstring>>} = Utils.deserialize_address(rest)

    {
      %ReplicationError{
        address: address,
        reason: ReplicationError.deserialize_reason(reason)
      },
      rest
    }
  end

  def decode(<<234::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {reason_size, rest} = VarInt.get_value(rest)

    case rest do
      <<reason::binary-size(reason_size), 0::8, rest::bitstring>> ->
        {%ValidationError{reason: reason, context: :network_issue, address: address}, rest}

      <<reason::binary-size(reason_size), 1::8, rest::bitstring>> ->
        {%ValidationError{reason: reason, context: :invalid_transaction, address: address}, rest}
    end
  end

  def decode(<<235::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%FirstAddress{address: address}, rest}
  end

  def decode(<<236::8, rest::bitstring>>) do
    {nb_transaction_attestations, rest} = rest |> VarInt.get_value()

    {transaction_attestations, rest} =
      Utils.deserialize_transaction_attestations(rest, nb_transaction_attestations, [])

    {
      %BeaconUpdate{
        transaction_attestations: transaction_attestations
      },
      rest
    }
  end

  def decode(<<237::8, rest::bitstring>>) do
    {nb_summaries, rest} = rest |> VarInt.get_value()
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
    {address, <<timestamp::64, rest::bitstring>>} = Utils.deserialize_address(rest)

    {%LastTransactionAddress{
       address: address,
       timestamp: DateTime.from_unix!(timestamp, :millisecond)
     }, rest}
  end

  def decode(<<242::8, rest::bitstring>>) do
    {public_key, rest} = Utils.deserialize_public_key(rest)
    {%FirstPublicKey{public_key: public_key}, rest}
  end

  def decode(<<243::8, view_size::8, rest::bitstring>>) do
    <<nodes_view::bitstring-size(view_size), rest::bitstring>> = rest
    {%P2PView{nodes_view: nodes_view}, rest}
  end

  def decode(<<244::8, rest::bitstring>>) do
    {nb_inputs, rest} = rest |> VarInt.get_value()

    {inputs, <<more_bit::1, rest::bitstring>>} =
      deserialize_versioned_transaction_inputs(rest, nb_inputs, [])

    more? = more_bit == 1

    {offset, rest} = VarInt.get_value(rest)

    {%TransactionInputList{
       inputs: inputs,
       more?: more?,
       offset: offset
     }, rest}
  end

  def decode(<<245::8, rest::bitstring>>) do
    {length, rest} = rest |> VarInt.get_value()

    {%TransactionChainLength{
       length: length
     }, rest}
  end

  def decode(<<246::8, rest::bitstring>>) do
    {nb_new_seeds, rest} = rest |> VarInt.get_value()
    {new_seeds, <<rest::bitstring>>} = deserialize_node_list(rest, nb_new_seeds, [])

    {nb_closest_nodes, rest} = rest |> VarInt.get_value()
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

  def decode(<<248::8, uco_balance::64, rest::bitstring>>) do
    {nb_token_balances, rest} = rest |> VarInt.get_value()
    {token_balances, rest} = deserialize_token_balances(rest, nb_token_balances, %{})

    {%Balance{
       uco: uco_balance,
       token: token_balances
     }, rest}
  end

  def decode(<<249::8, rest::bitstring>>) do
    {nb_nodes, rest} = rest |> VarInt.get_value()
    {nodes, rest} = deserialize_node_list(rest, nb_nodes, [])
    {%NodeList{nodes: nodes}, rest}
  end

  def decode(<<250::8, rest::bitstring>>) do
    {nb_unspent_outputs, rest} = rest |> VarInt.get_value()

    {unspent_outputs, <<more_bit::1, rest::bitstring>>} =
      deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, [])

    more? = more_bit == 1

    {offset, rest} = VarInt.get_value(rest)

    {%UnspentOutputList{unspent_outputs: unspent_outputs, more?: more?, offset: offset}, rest}
  end

  def decode(<<251::8, rest::bitstring>>) do
    {nb_transactions, rest} = rest |> VarInt.get_value()
    {transactions, rest} = deserialize_tx_list(rest, nb_transactions, [])

    case rest do
      <<0::1, rest::bitstring>> ->
        {
          %TransactionList{transactions: transactions, more?: false},
          rest
        }

      <<1::1, paging_state_size::8, paging_state::binary-size(paging_state_size),
        rest::bitstring>> ->
        {
          %TransactionList{transactions: transactions, more?: true, paging_state: paging_state},
          rest
        }
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

  defp deserialize_versioned_unspent_output_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, acc)
       when length(acc) == nb_unspent_outputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_versioned_unspent_output_list(
         rest,
         nb_unspent_outputs,
         acc
       ) do
    {unspent_output, rest} = VersionedUnspentOutput.deserialize(rest)

    deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, [unspent_output | acc])
  end

  defp deserialize_versioned_transaction_inputs(rest, 0, _acc), do: {[], rest}

  defp deserialize_versioned_transaction_inputs(rest, nb_inputs, acc)
       when length(acc) == nb_inputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_versioned_transaction_inputs(
         rest,
         nb_inputs,
         acc
       ) do
    {input, rest} = VersionedTransactionInput.deserialize(rest)
    deserialize_versioned_transaction_inputs(rest, nb_inputs, [input | acc])
  end

  defp deserialize_token_balances(rest, 0, _acc), do: {%{}, rest}

  defp deserialize_token_balances(rest, token_balances, acc)
       when map_size(acc) == token_balances do
    {acc, rest}
  end

  defp deserialize_token_balances(rest, nb_token_balances, acc) do
    {token_address, <<amount::64, rest::bitstring>>} = Utils.deserialize_address(rest)
    {token_id, rest} = VarInt.get_value(rest)

    deserialize_token_balances(
      rest,
      nb_token_balances,
      Map.put(acc, {token_address, token_id}, amount)
    )
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
  @spec process(request(), Crypto.key()) :: response()
  def process(%GetBootstrappingNodes{patch: patch}, _) do
    top_nodes = P2P.authorized_and_available_nodes()

    closest_nodes =
      top_nodes
      |> P2P.nearest_nodes(patch)
      |> Enum.take(5)

    %BootstrappingNodes{
      new_seeds: Enum.take_random(top_nodes, 5),
      closest_nodes: closest_nodes
    }
  end

  def process(%GetStorageNonce{public_key: public_key}, _) do
    %EncryptedStorageNonce{
      digest: Crypto.encrypt_storage_nonce(public_key)
    }
  end

  def process(%ListNodes{}, _) do
    %NodeList{nodes: P2P.list_nodes()}
  end

  def process(%NewTransaction{transaction: tx}, _) do
    case Archethic.send_new_transaction(tx) do
      :ok ->
        %Ok{}

      {:error, :network_issue} ->
        %Error{reason: :network_issue}
    end
  end

  def process(%ValidationError{context: context, reason: reason, address: address}, _) do
    TransactionSubscriber.report_error(address, context, reason)
    %Ok{}
  end

  def process(%GetTransaction{address: tx_address}, _) do
    case TransactionChain.get_transaction(tx_address) do
      {:ok, tx} ->
        tx

      {:error, :transaction_not_exists} ->
        %NotFound{}

      {:error, :invalid_transaction} ->
        %Error{reason: :invalid_transaction}
    end
  end

  # paging_state recieved  contains binary offset for next page , to be used for query
  def process(
        %GetTransactionChain{
          address: tx_address,
          paging_state: paging_state
        },
        _
      ) do
    {chain, more?, paging_state} =
      tx_address
      |> TransactionChain.get([], paging_state: paging_state)

    # empty list for fields/cols to be processed
    # new_page_state contains binary offset for the next page
    %TransactionList{transactions: chain, paging_state: paging_state, more?: more?}
  end

  def process(%GetUnspentOutputs{address: tx_address, offset: offset}, _) do
    utxos = Account.get_unspent_outputs(tx_address)
    utxos_length = length(utxos)

    %{utxos: utxos, offset: offset, more?: more?} =
      utxos
      # |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
      |> Enum.with_index()
      |> Enum.drop(offset)
      |> Enum.reduce_while(%{utxos: [], offset: 0, more?: false}, fn {versioned_utxo, index},
                                                                     acc ->
        acc_size =
          acc.utxos
          |> Enum.map(&VersionedUnspentOutput.serialize/1)
          |> :erlang.list_to_binary()
          |> byte_size()

        utxo_size =
          versioned_utxo
          |> VersionedUnspentOutput.serialize()
          |> byte_size

        if acc_size + utxo_size < 3_000_000 do
          new_acc =
            acc
            |> Map.update!(:utxos, &[versioned_utxo | &1])
            |> Map.put(:offset, index + 1)
            |> Map.put(:more?, index + 1 < utxos_length)

          {:cont, new_acc}
        else
          {:halt, acc}
        end
      end)

    %UnspentOutputList{
      unspent_outputs: utxos,
      offset: offset,
      more?: more?
    }
  end

  def process(%GetP2PView{node_public_keys: node_public_keys}, _) do
    nodes =
      Enum.map(node_public_keys, fn key ->
        {:ok, node} = P2P.get_node_info(key)
        node
      end)

    view = P2P.nodes_availability_as_bits(nodes)
    %P2PView{nodes_view: view}
  end

  def process(
        %StartMining{
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

  def process(
        %AddMiningContext{
          address: tx_address,
          validation_node_public_key: validation_node,
          previous_storage_nodes_public_keys: previous_storage_nodes_public_keys,
          chain_storage_nodes_view: chain_storage_nodes_view,
          beacon_storage_nodes_view: beacon_storage_nodes_view,
          io_storage_nodes_view: io_storage_nodes_view
        },
        _
      ) do
    :ok =
      Mining.add_mining_context(
        tx_address,
        validation_node,
        previous_storage_nodes_public_keys,
        chain_storage_nodes_view,
        beacon_storage_nodes_view,
        io_storage_nodes_view
      )

    %Ok{}
  end

  def process(
        %ReplicateTransactionChain{
          transaction:
            tx = %Transaction{
              address: tx_address,
              type: tx_type,
              validation_stamp: %ValidationStamp{timestamp: timestamp}
            },
          replying_node: replying_node_public_key
        },
        _
      ) do
    # We don't check the election for network transactions because all the nodes receive the chain replication message
    # The chain storage nodes election is all the authorized nodes but during I/O replication, we send this message to enforce
    # the synchronization of the network chains
    if Transaction.network_type?(tx_type) do
      process_replication_chain(tx, replying_node_public_key)
    else
      storage_nodes =
        Election.chain_storage_nodes_with_type(
          tx_address,
          tx_type,
          P2P.authorized_and_available_nodes(timestamp)
        )

      # Replicate transaction chain only if the current node is one of the chain storage nodes
      if Utils.key_in_node_list?(storage_nodes, Crypto.first_node_public_key()) do
        process_replication_chain(tx, replying_node_public_key)
      end
    end

    %Ok{}
  end

  def process(
        %ReplicateTransaction{
          transaction:
            tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: validation_time}}
        },
        _
      ) do
    resolved_addresses = TransactionChain.resolve_transaction_addresses(tx, validation_time)

    io_storage_nodes =
      if Transaction.network_type?(tx.type) do
        P2P.list_nodes()
      else
        resolved_addresses
        |> Enum.map(fn {_origin, resolved} -> resolved end)
        |> Enum.concat([LedgerOperations.burning_address()])
        |> Election.io_storage_nodes(P2P.authorized_and_available_nodes(validation_time))
      end

    # Replicate tx only if the current node is one of the I/O storage nodes
    if Utils.key_in_node_list?(io_storage_nodes, Crypto.first_node_public_key()) do
      case Replication.validate_and_store_transaction(tx) do
        :ok ->
          %Ok{}

        {:error, :transaction_already_exists} ->
          %ReplicationError{address: tx.address, reason: :transaction_already_exists}

        {:error, invalid_tx_reason} ->
          %ReplicationError{address: tx.address, reason: invalid_tx_reason}
      end
    else
      %Ok{}
    end
  end

  def process(
        %AcknowledgeStorage{
          address: address,
          signature: signature,
          node_public_key: node_public_key
        },
        _
      ) do
    Mining.confirm_replication(address, signature, node_public_key)
    %Ok{}
  end

  def process(
        %ReplicationError{
          address: address,
          reason: reason
        },
        _
      ) do
    Mining.notify_replication_error(address, reason)
    %Ok{}
  end

  def process(
        %CrossValidate{
          address: tx_address,
          validation_stamp: stamp,
          replication_tree: replication_tree,
          confirmed_validation_nodes: confirmed_validation_nodes
        },
        _
      ) do
    Mining.cross_validate(tx_address, stamp, replication_tree, confirmed_validation_nodes)
    %Ok{}
  end

  def process(%CrossValidationDone{address: tx_address, cross_validation_stamp: stamp}, _) do
    Mining.add_cross_validation_stamp(tx_address, stamp)
    %Ok{}
  end

  def process(%NotifyEndOfNodeSync{node_public_key: public_key, timestamp: timestamp}, _) do
    BeaconChain.add_end_of_node_sync(public_key, timestamp)
    %Ok{}
  end

  def process(%GetLastTransaction{address: address}, _) do
    case TransactionChain.get_last_transaction(address) do
      {:ok, tx} ->
        tx

      {:error, :transaction_not_exists} ->
        %NotFound{}

      {:error, :invalid_transaction} ->
        %Error{reason: :invalid_transaction}
    end
  end

  def process(%GetBalance{address: address}, _) do
    %{uco: uco, token: token} = Account.get_balance(address)

    %Balance{
      uco: uco,
      token: token
    }
  end

  def process(%GetTransactionInputs{address: address, offset: offset, limit: limit}, _) do
    contract_inputs =
      address
      |> Contracts.list_contract_transactions()
      |> Enum.map(fn {address, timestamp} ->
        %TransactionInput{from: address, type: :call, timestamp: timestamp}
      end)

    inputs = Account.get_inputs(address) ++ contract_inputs
    inputs_length = length(inputs)

    %{inputs: inputs, offset: offset, more?: more?} =
      inputs
      |> Enum.sort_by(& &1.input.timestamp, {:desc, DateTime})
      |> Enum.with_index()
      |> Enum.drop(offset)
      |> Enum.reduce_while(%{inputs: [], offset: 0, more?: false}, fn {versioned_input, index},
                                                                      acc ->
        acc_size =
          acc.inputs
          |> Enum.map(&VersionedTransactionInput.serialize/1)
          |> :erlang.list_to_bitstring()
          |> byte_size()

        input_size =
          versioned_input
          |> VersionedTransactionInput.serialize()
          |> byte_size

        size_capacity? = acc_size + input_size < 3_000_000

        should_take_more? =
          if limit > 0 do
            length(acc.inputs) < limit and size_capacity?
          else
            size_capacity?
          end

        if should_take_more? do
          new_acc =
            acc
            |> Map.update!(:inputs, &[versioned_input | &1])
            |> Map.put(:offset, index + 1)
            |> Map.put(:more?, index + 1 < inputs_length)

          {:cont, new_acc}
        else
          {:halt, acc}
        end
      end)

    %TransactionInputList{
      inputs: Enum.reverse(inputs),
      more?: more?,
      offset: offset
    }
  end

  # Returns the length of the transaction chain
  def process(%GetTransactionChainLength{address: address}, _) do
    %TransactionChainLength{
      length: TransactionChain.size(address)
    }
  end

  # Returns the first public_key for a given public_key and if the public_key is used for the first time, return the same public_key.
  def process(%GetFirstPublicKey{public_key: public_key}, _) do
    %FirstPublicKey{
      public_key: TransactionChain.get_first_public_key(public_key)
    }
  end

  def process(%GetFirstAddress{address: address}, _) do
    genesis_address = TransactionChain.get_genesis_address(address)
    %FirstAddress{address: genesis_address}
  end

  def process(%GetLastTransactionAddress{address: address, timestamp: timestamp}, _) do
    {address, time} = TransactionChain.get_last_address(address, timestamp)
    %LastTransactionAddress{address: address, timestamp: time}
  end

  def process(
        %NotifyLastTransactionAddress{
          last_address: last_address,
          genesis_address: genesis_address,
          timestamp: timestamp
        },
        _
      ) do
    with {local_last_address, local_last_timestamp} <-
           TransactionChain.get_last_address(genesis_address),
         true <- local_last_address != last_address,
         :gt <- DateTime.compare(timestamp, local_last_timestamp) do
      TransactionChain.register_last_address(genesis_address, last_address, timestamp)

      # Stop potential previous smart contract
      Contracts.stop_contract(local_last_address)
    end

    %Ok{}
  end

  def process(%GetTransactionSummary{address: address}, _) do
    case TransactionChain.get_transaction_summary(address) do
      {:ok, summary} ->
        summary

      {:error, :not_found} ->
        %NotFound{}
    end
  end

  def process(%GetCurrentSummaries{subsets: subsets}, _) do
    transaction_summaries =
      Enum.flat_map(subsets, fn subset ->
        transaction_summaries = BeaconChain.get_summary_slots(subset)

        %Slot{transaction_attestations: transaction_attestations} =
          Subset.get_current_slot(subset)

        Enum.reduce(
          transaction_attestations,
          transaction_summaries,
          &[&1.transaction_summary | &2]
        )
      end)

    %TransactionSummaryList{
      transaction_summaries: transaction_summaries
    }
  end

  def process(%Ping{}, _), do: %Ok{}

  def process(%GetBeaconSummary{address: address}, _) do
    case BeaconChain.get_summary(address) do
      {:ok, summary} ->
        summary

      {:error, :not_found} ->
        %NotFound{}
    end
  end

  def process(%NewBeaconSlot{slot: slot = %Slot{subset: subset, slot_time: slot_time}}, _) do
    summary_time = BeaconChain.next_summary_date(slot_time)
    node_list = P2P.authorized_and_available_nodes(summary_time)

    beacon_summary_nodes =
      Election.beacon_storage_nodes(
        subset,
        summary_time,
        node_list,
        Election.get_storage_constraints()
      )

    # Load BeaconChain's slot only for the summary nodes
    with true <- Utils.key_in_node_list?(beacon_summary_nodes, Crypto.first_node_public_key()),
         :ok <- BeaconChain.load_slot(slot) do
      %Ok{}
    else
      false ->
        Logger.error("Unexpected beacon slot broadcast")
        %Error{reason: :network_issue}

      :error ->
        %Error{reason: :invalid_transaction}
    end
  end

  def process(%GetBeaconSummaries{addresses: addresses}, _) do
    %BeaconSummaryList{
      summaries: BeaconChain.get_beacon_summaries(addresses)
    }
  end

  def process(%RegisterBeaconUpdates{node_public_key: node_public_key, subset: subset}, _) do
    BeaconChain.subscribe_for_beacon_updates(subset, node_public_key)
    %Ok{}
  end

  def process(%BeaconUpdate{transaction_attestations: transaction_attestations}, sender) do
    Enum.each(transaction_attestations, fn %ReplicationAttestation{
                                             transaction_summary: tx_summary
                                           } ->
      process(tx_summary, sender)
    end)

    %Ok{}
  end

  def process(tx_summary = %TransactionSummary{}, _) do
    PubSub.notify_transaction_attestation(tx_summary)

    %Ok{}
  end

  def process(
        attestation = %ReplicationAttestation{
          transaction_summary: %TransactionSummary{address: tx_address, type: tx_type}
        },
        _
      ) do
    case ReplicationAttestation.validate(attestation) do
      :ok ->
        PubSub.notify_replication_attestation(attestation)
        %Ok{}

      {:error, :invalid_confirmations_signatures} ->
        Logger.error("Invalid attestation signatures",
          transaction_address: Base.encode16(tx_address),
          transaction_type: tx_type
        )

        %Error{reason: :invalid_attestation}
    end
  end

  def process(%GetBeaconSummariesAggregate{date: date}, _) do
    case BeaconChain.get_summaries_aggregate(date) do
      {:ok, aggregate} ->
        aggregate

      {:error, :not_exists} ->
        %NotFound{}
    end
  end

  def process(%NotifyPreviousChain{address: address}, _) do
    Replication.acknowledge_previous_storage_nodes(address)
    %Ok{}
  end

  def process(
        msg = %ShardRepair{
          first_address: first_address,
          last_address: last_address
        },
        _
      ) do
    alias Archethic.SelfRepair.Notifier.Impl, as: NotifierImpl

    with {:exists?, false} <- {:exists?, TransactionChain.transaction_exists?(last_address)},
         {:worker?, false} <- {:worker?, NotifierImpl.repair_in_progress?(first_address)} do
      msg
      |> NotifierImpl.start_worker()

      NotifierImpl.log(:debug, "Repair Started", first_address, last_address, "none")
    else
      {:exists?, true} ->
        # corner case: check if the complete chain exists or not?
        NotifierImpl.log(
          :debug,
          "Message.Process Txn exists",
          first_address,
          last_address,
          "none"
        )

        :ok

      {:worker?, pid} when is_pid(pid) ->
        msg
        |> NotifierImpl.update_worker(pid)

        NotifierImpl.log(
          :debug,
          "New-Message: WorkerUpdated",
          first_address,
          last_address,
          "none"
        )
    end

    %Ok{}
  end

  defp process_replication_chain(tx, replying_node_public_key) do
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      response =
        case Replication.validate_and_store_transaction_chain(tx) do
          :ok ->
            tx_summary = TransactionSummary.from_transaction(tx)

            %AcknowledgeStorage{
              address: tx.address,
              signature:
                Crypto.sign_with_first_node_key(TransactionSummary.serialize(tx_summary)),
              node_public_key: Crypto.first_node_public_key()
            }

          {:error, :transaction_already_exists} ->
            %ReplicationError{address: tx.address, reason: :transaction_already_exists}

          {:error, invalid_tx_error} ->
            %ReplicationError{address: tx.address, reason: invalid_tx_error}
        end

      if replying_node_public_key do
        P2P.send_message(replying_node_public_key, response)
      end
    end)
  end
end
