defmodule Archethic.P2P.MessageId do
  @moduledoc """
  Provide functions to convert struct to message id and message id to struct
  """

  alias Archethic.P2P.Message.{
    GetBootstrappingNodes,
    GetStorageNonce,
    ListNodes,
    GetTransaction,
    GetTransactionChain,
    GetUnspentOutputs,
    NewTransaction,
    StartMining,
    AddMiningContext,
    CrossValidate,
    CrossValidationDone,
    ReplicateTransactionChain,
    ReplicateTransaction,
    AcknowledgeStorage,
    NotifyEndOfNodeSync,
    GetLastTransaction,
    GetBalance,
    GetTransactionInputs,
    GetTransactionChainLength,
    GetP2PView,
    GetFirstPublicKey,
    NotifyLastTransactionAddress,
    GetTransactionSummary,
    Ping,
    GetBeaconSummary,
    NewBeaconSlot,
    GetBeaconSummaries,
    RegisterBeaconUpdates,
    GetGenesisAddress,
    GetCurrentSummaries,
    GetBeaconSummariesAggregate,
    NotifyPreviousChain,
    GetNextAddresses,
    AddressList,
    ShardRepair,
    TransactionSummaryList,
    ReplicationError,
    ValidationError,
    GenesisAddress,
    BeaconUpdate,
    BeaconSummaryList,
    Error,
    LastTransactionAddress,
    FirstPublicKey,
    P2PView,
    TransactionInputList,
    TransactionChainLength,
    BootstrappingNodes,
    EncryptedStorageNonce,
    Balance,
    NodeList,
    UnspentOutputList,
    TransactionList,
    GetLastTransactionAddress,
    NotFound,
    Ok,
    ValidateTransaction,
    ReplicatePendingTransactionChain,
    NotifyReplicationValidation,
    TransactionSummaryMessage,
    ReplicationAttestationMessage
  }

  alias Archethic.TransactionChain.{
    Transaction
  }

  alias Archethic.BeaconChain.{
    Summary,
    SummaryAggregate
  }

  @message_ids %{
    # Requests
    GetBootstrappingNodes => 0,
    GetStorageNonce => 1,
    ListNodes => 2,
    GetTransaction => 3,
    GetTransactionChain => 4,
    GetUnspentOutputs => 5,
    NewTransaction => 6,
    StartMining => 7,
    AddMiningContext => 8,
    CrossValidate => 9,
    CrossValidationDone => 10,
    ReplicateTransactionChain => 11,
    ReplicateTransaction => 12,
    AcknowledgeStorage => 13,
    NotifyEndOfNodeSync => 14,
    GetLastTransaction => 15,
    GetBalance => 16,
    GetTransactionInputs => 17,
    GetTransactionChainLength => 18,
    GetP2PView => 19,
    GetFirstPublicKey => 20,
    GetLastTransactionAddress => 21,
    NotifyLastTransactionAddress => 22,
    GetTransactionSummary => 23,
    # id 24 is available for a new message
    Ping => 25,
    GetBeaconSummary => 26,
    NewBeaconSlot => 27,
    GetBeaconSummaries => 28,
    RegisterBeaconUpdates => 29,
    ReplicationAttestationMessage => 30,
    GetGenesisAddress => 31,
    GetCurrentSummaries => 32,
    GetBeaconSummariesAggregate => 33,
    NotifyPreviousChain => 34,
    GetNextAddresses => 35,
    ValidateTransaction => 36,
    ReplicatePendingTransactionChain => 37,
    NotifyReplicationValidation => 38,

    # Responses
    AddressList => 229,
    ShardRepair => 230,
    SummaryAggregate => 231,
    TransactionSummaryList => 232,
    ReplicationError => 233,
    ValidationError => 234,
    GenesisAddress => 235,
    BeaconUpdate => 236,
    BeaconSummaryList => 237,
    Error => 238,
    TransactionSummaryMessage => 239,
    Summary => 240,
    LastTransactionAddress => 241,
    FirstPublicKey => 242,
    P2PView => 243,
    TransactionInputList => 244,
    TransactionChainLength => 245,
    BootstrappingNodes => 246,
    EncryptedStorageNonce => 247,
    Balance => 248,
    NodeList => 249,
    UnspentOutputList => 250,
    TransactionList => 251,
    Transaction => 252,
    NotFound => 253,
    Ok => 254
  }

  defmacro __before_compile__(_env) do
    Enum.map(@message_ids, fn {msg, msg_id} ->
      quote do
        def id_to_module(unquote(msg_id)), do: unquote(msg)
        def module_to_id(unquote(msg)), do: unquote(msg_id)
      end
    end)
  end
end
