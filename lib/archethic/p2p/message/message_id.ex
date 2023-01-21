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
    GetFirstTransactionAddress,
    FirstTransactionAddress,
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

  @spec id_to_module(0..256) :: atom()
  # Requests
  def id_to_module(0), do: GetBootstrappingNodes
  def id_to_module(1), do: GetStorageNonce
  def id_to_module(2), do: ListNodes
  def id_to_module(3), do: GetTransaction
  def id_to_module(4), do: GetTransactionChain
  def id_to_module(5), do: GetUnspentOutputs
  def id_to_module(6), do: NewTransaction
  def id_to_module(7), do: StartMining
  def id_to_module(8), do: AddMiningContext
  def id_to_module(9), do: CrossValidate
  def id_to_module(10), do: CrossValidationDone
  def id_to_module(11), do: ReplicateTransactionChain
  def id_to_module(12), do: ReplicateTransaction
  def id_to_module(13), do: AcknowledgeStorage
  def id_to_module(14), do: NotifyEndOfNodeSync
  def id_to_module(15), do: GetLastTransaction
  def id_to_module(16), do: GetBalance
  def id_to_module(17), do: GetTransactionInputs
  def id_to_module(18), do: GetTransactionChainLength
  def id_to_module(19), do: GetP2PView
  def id_to_module(20), do: GetFirstPublicKey
  def id_to_module(21), do: GetLastTransactionAddress
  def id_to_module(22), do: NotifyLastTransactionAddress
  def id_to_module(23), do: GetTransactionSummary
  def id_to_module(24), do: GetFirstTransactionAddress
  def id_to_module(25), do: Ping
  def id_to_module(26), do: GetBeaconSummary
  def id_to_module(27), do: NewBeaconSlot
  def id_to_module(28), do: GetBeaconSummaries
  def id_to_module(29), do: RegisterBeaconUpdates
  def id_to_module(30), do: ReplicationAttestationMessage
  def id_to_module(31), do: GetGenesisAddress
  def id_to_module(32), do: GetCurrentSummaries
  def id_to_module(33), do: GetBeaconSummariesAggregate
  def id_to_module(34), do: NotifyPreviousChain
  def id_to_module(35), do: GetNextAddresses
  def id_to_module(36), do: ValidateTransaction
  def id_to_module(37), do: ReplicatePendingTransactionChain
  def id_to_module(38), do: NotifyReplicationValidation

  # Responses
  def id_to_module(228), do: FirstTransactionAddress
  def id_to_module(229), do: AddressList
  def id_to_module(230), do: ShardRepair
  def id_to_module(231), do: SummaryAggregate
  def id_to_module(232), do: TransactionSummaryList
  def id_to_module(233), do: ReplicationError
  def id_to_module(234), do: ValidationError
  def id_to_module(235), do: GenesisAddress
  def id_to_module(236), do: BeaconUpdate
  def id_to_module(237), do: BeaconSummaryList
  def id_to_module(238), do: Error
  def id_to_module(239), do: TransactionSummaryMessage
  def id_to_module(240), do: Summary
  def id_to_module(241), do: LastTransactionAddress
  def id_to_module(242), do: FirstPublicKey
  def id_to_module(243), do: P2PView
  def id_to_module(244), do: TransactionInputList
  def id_to_module(245), do: TransactionChainLength
  def id_to_module(246), do: BootstrappingNodes
  def id_to_module(247), do: EncryptedStorageNonce
  def id_to_module(248), do: Balance
  def id_to_module(249), do: NodeList
  def id_to_module(250), do: UnspentOutputList
  def id_to_module(251), do: TransactionList
  def id_to_module(252), do: Transaction
  def id_to_module(253), do: NotFound
  def id_to_module(254), do: Ok

  @spec module_to_id(atom()) :: integer()
  # Requests
  def module_to_id(GetBootstrappingNodes), do: 0
  def module_to_id(GetStorageNonce), do: 1
  def module_to_id(ListNodes), do: 2
  def module_to_id(GetTransaction), do: 3
  def module_to_id(GetTransactionChain), do: 4
  def module_to_id(GetUnspentOutputs), do: 5
  def module_to_id(NewTransaction), do: 6
  def module_to_id(StartMining), do: 7
  def module_to_id(AddMiningContext), do: 8
  def module_to_id(CrossValidate), do: 9
  def module_to_id(CrossValidationDone), do: 10
  def module_to_id(ReplicateTransactionChain), do: 11
  def module_to_id(ReplicateTransaction), do: 12
  def module_to_id(AcknowledgeStorage), do: 13
  def module_to_id(NotifyEndOfNodeSync), do: 14
  def module_to_id(GetLastTransaction), do: 15
  def module_to_id(GetBalance), do: 16
  def module_to_id(GetTransactionInputs), do: 17
  def module_to_id(GetTransactionChainLength), do: 18
  def module_to_id(GetP2PView), do: 19
  def module_to_id(GetFirstPublicKey), do: 20
  def module_to_id(GetLastTransactionAddress), do: 21
  def module_to_id(NotifyLastTransactionAddress), do: 22
  def module_to_id(GetTransactionSummary), do: 23
  def module_to_id(GetFirstTransactionAddress), do: 24
  def module_to_id(Ping), do: 25
  def module_to_id(GetBeaconSummary), do: 26
  def module_to_id(NewBeaconSlot), do: 27
  def module_to_id(GetBeaconSummaries), do: 28
  def module_to_id(RegisterBeaconUpdates), do: 29
  def module_to_id(ReplicationAttestationMessage), do: 30
  def module_to_id(GetGenesisAddress), do: 31
  def module_to_id(GetCurrentSummaries), do: 32
  def module_to_id(GetBeaconSummariesAggregate), do: 33
  def module_to_id(NotifyPreviousChain), do: 34
  def module_to_id(GetNextAddresses), do: 35
  def module_to_id(ValidateTransaction), do: 36
  def module_to_id(ReplicatePendingTransactionChain), do: 37
  def module_to_id(NotifyReplicationValidation), do: 38

  # Responses
  def module_to_id(FirstTransactionAddress), do: 228
  def module_to_id(AddressList), do: 229
  def module_to_id(ShardRepair), do: 230
  def module_to_id(SummaryAggregate), do: 231
  def module_to_id(TransactionSummaryList), do: 232
  def module_to_id(ReplicationError), do: 233
  def module_to_id(ValidationError), do: 234
  def module_to_id(GenesisAddress), do: 235
  def module_to_id(BeaconUpdate), do: 236
  def module_to_id(BeaconSummaryList), do: 237
  def module_to_id(Error), do: 238
  def module_to_id(TransactionSummaryMessage), do: 239
  def module_to_id(Summary), do: 240
  def module_to_id(LastTransactionAddress), do: 241
  def module_to_id(FirstPublicKey), do: 242
  def module_to_id(P2PView), do: 243
  def module_to_id(TransactionInputList), do: 244
  def module_to_id(TransactionChainLength), do: 245
  def module_to_id(BootstrappingNodes), do: 246
  def module_to_id(EncryptedStorageNonce), do: 247
  def module_to_id(Balance), do: 248
  def module_to_id(NodeList), do: 249
  def module_to_id(UnspentOutputList), do: 250
  def module_to_id(TransactionList), do: 251
  def module_to_id(Transaction), do: 252
  def module_to_id(NotFound), do: 253
  def module_to_id(Ok), do: 254
end
