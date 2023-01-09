defmodule ArchethicWeb.ReferenceTransaction do
  @moduledoc """
  ReferenceTransaction is a subset of a transaction
  It is meant to be cached so we use a lighter structure
  """
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias ArchethicCache.LRU

  @enforce_keys [:address, :json_content, :timestamp, :ownerships]
  defstruct [:address, :json_content, :timestamp, :ownerships]

  @type t() :: %__MODULE__{
          address: binary(),
          json_content: map(),
          timestamp: DateTime.t(),
          ownerships: list(Ownership.t())
        }

  @doc """
  Fetch the reference transaction either from cache, or from the network.
  """
  @spec fetch(binary()) :: {:ok, t()} | {:error, term()}
  def fetch(address) do
    # started by ArchethicWeb.Supervisor
    cache_server = :web_hosting_cache_ref_tx
    cache_key = address

    case LRU.get(cache_server, cache_key) do
      nil ->
        with {:ok, transaction} <- Archethic.search_transaction(address),
             {:ok, reference_transaction} <- from_transaction(transaction) do
          :telemetry.execute([:archethic_web, :hosting, :cache_ref_tx, :miss], %{count: 1})
          LRU.put(cache_server, cache_key, reference_transaction)
          {:ok, reference_transaction}
        end

      reference_transaction ->
        :telemetry.execute([:archethic_web, :hosting, :cache_ref_tx, :hit], %{count: 1})
        {:ok, reference_transaction}
    end
  end

  @doc """
  Fetch the latest reference transaction of the chain, either from cache, or from the network.
  """
  @spec fetch_last(binary()) :: {:ok, t()} | {:error, term()}
  def fetch_last(address) do
    with {:ok, last_address} <- Archethic.get_last_transaction_address(address) do
      fetch(last_address)
    end
  end

  defp from_transaction(%Transaction{
         address: address,
         data: %TransactionData{content: content, ownerships: ownerships},
         validation_stamp: %ValidationStamp{timestamp: timestamp}
       }) do
    with {:ok, json_content} <- Jason.decode(content) do
      {:ok,
       %__MODULE__{
         address: address,
         json_content: json_content,
         timestamp: timestamp,
         ownerships: ownerships
       }}
    end
  end
end
