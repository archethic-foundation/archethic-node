defmodule Archethic.P2P.Message do
  @moduledoc """
  Provide functions to encode and decode P2P messages using a custom binary protocol
  """

  alias Archethic.Crypto

  alias Archethic.P2P.MessageId

  alias Archethic.BeaconChain.{
    Summary,
    SummaryAggregate
  }

  alias Archethic.TransactionChain.Transaction

  alias __MODULE__.{
    AddressList,
    BeaconSummaryList,
    BeaconUpdate,
    BootstrappingNodes,
    CrossValidate,
    CrossValidationDone,
    EncryptedStorageNonce,
    Error,
    FirstPublicKey,
    GenesisAddress,
    GetGenesisAddress,
    GetBeaconSummaries,
    GetBeaconSummary,
    GetBeaconSummariesAggregate,
    GetBootstrappingNodes,
    GetCurrentSummaries,
    GetCurrentReplicationAttestations,
    GetCurrentReplicationAttestationsResponse,
    GetLastTransaction,
    GetLastTransactionAddress,
    GetNextAddresses,
    GetStorageNonce,
    GetTransaction,
    GetTransactionChain,
    GetTransactionChainLength,
    GetTransactionInputs,
    GetUnspentOutputs,
    GetFirstTransactionAddress,
    FirstTransactionAddress,
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
    Ping,
    RegisterBeaconUpdates,
    ReplicateTransaction,
    ReplicationError,
    RequestChainLock,
    ShardRepair,
    StartMining,
    TransactionChainLength,
    TransactionInputList,
    TransactionSummaryList,
    TransactionList,
    UnspentOutputList,
    ValidationError,
    AddMiningContext,
    ValidateTransaction,
    ReplicatePendingTransactionChain,
    NotifyReplicationValidation,
    TransactionSummaryMessage,
    AcknowledgeStorage,
    ReplicationAttestationMessage,
    GetTransactionSummary,
    GetNetworkStats,
    NetworkStats,
    ValidateSmartContractCall,
    SmartContractCallValidation,
    GetDashboardData,
    DashboardData,
    UnlockChain
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
          | NewTransaction.t()
          | StartMining.t()
          | AddMiningContext.t()
          | CrossValidate.t()
          | CrossValidationDone.t()
          | ReplicateTransaction.t()
          | GetLastTransaction.t()
          | GetTransactionInputs.t()
          | GetTransactionChainLength.t()
          | GetFirstTransactionAddress.t()
          | FirstTransactionAddress.t()
          | NotifyEndOfNodeSync.t()
          | GetLastTransactionAddress.t()
          | NotifyLastTransactionAddress.t()
          | Ping.t()
          | GetBeaconSummary.t()
          | NewBeaconSlot.t()
          | GetBeaconSummaries.t()
          | RegisterBeaconUpdates.t()
          | BeaconUpdate.t()
          | TransactionSummaryMessage.t()
          | ReplicationAttestationMessage.t()
          | GetGenesisAddress.t()
          | ValidationError.t()
          | GetCurrentSummaries.t()
          | GetCurrentReplicationAttestations.t()
          | GetBeaconSummariesAggregate.t()
          | NotifyPreviousChain.t()
          | ShardRepair.t()
          | GetNextAddresses.t()
          | ValidateTransaction.t()
          | ReplicatePendingTransactionChain.t()
          | NotifyReplicationValidation.t()
          | AcknowledgeStorage.t()
          | GetTransactionSummary.t()
          | GetNetworkStats.t()
          | ValidateSmartContractCall.t()
          | GetDashboardData.t()
          | RequestChainLock.t()
          | UnlockChain.t()

  @type response ::
          Ok.t()
          | NotFound.t()
          | TransactionList.t()
          | Transaction.t()
          | NodeList.t()
          | UnspentOutputList.t()
          | EncryptedStorageNonce.t()
          | BootstrappingNodes.t()
          | TransactionSummaryMessage.t()
          | LastTransactionAddress.t()
          | FirstPublicKey.t()
          | TransactionChainLength.t()
          | TransactionInputList.t()
          | TransactionSummaryList.t()
          | Error.t()
          | Summary.t()
          | BeaconSummaryList.t()
          | GenesisAddress.t()
          | ReplicationError.t()
          | SummaryAggregate.t()
          | AddressList.t()
          | NetworkStats.t()
          | SmartContractCallValidation.t()
          | DashboardData.t()
          | GetCurrentReplicationAttestationsResponse.t()

  @floor_upload_speed Application.compile_env!(:archethic, [__MODULE__, :floor_upload_speed])
  @content_max_size Application.compile_env!(:archethic, :transaction_data_content_max_size)

  @before_compile MessageId

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
  def get_timeout(%ValidateTransaction{}), do: get_max_timeout()

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
  Decode an encoded message
  """
  @spec decode(bitstring()) :: {t(), bitstring}
  def decode(<<255::8>>), do: raise("255 message type is reserved for stream EOF")

  @doc """
  Handle a P2P message by processing it and return list of responses to be streamed back to the client
  """
  @spec process(request(), Crypto.key()) :: response()
  def process(msg, key), do: msg.__struct__.process(msg, key)
end
