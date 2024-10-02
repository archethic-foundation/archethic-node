defmodule Archethic.DB do
  @moduledoc false

  alias Archethic.BeaconChain.Summary
  alias Archethic.BeaconChain.SummaryAggregate

  alias Archethic.Crypto

  alias __MODULE__.EmbeddedImpl

  alias Archethic.TransactionChain.Transaction

  use Knigge, otp_app: :archethic, default: EmbeddedImpl

  @type storage_type() :: :chain | :io

  @callback get_transaction(address :: binary()) ::
              {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  @callback get_transaction(address :: binary(), fields :: list()) ::
              {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  @callback get_transaction(address :: binary(), fields :: list(), storage_type :: storage_type()) ::
              {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  @callback get_beacon_summary(summary_address :: binary()) ::
              {:ok, Summary.t()} | {:error, :summary_not_exists}
  @callback get_beacon_summaries_aggregate(DateTime.t()) ::
              {:ok, SummaryAggregate.t()} | {:error, :not_exists}
  @callback get_transaction_chain(
              binary(),
              fields :: list(),
              opts :: [
                paging_address: nil | binary(),
                after: DateTime.t(),
                order: :asc | :desc
              ]
            ) :: Enumerable.t()
  @callback write_transaction(Transaction.t(), storage_type()) :: :ok
  @callback write_beacon_summary(Summary.t()) :: :ok
  @callback clear_beacon_summaries() :: :ok
  @callback write_beacon_summaries_aggregate(SummaryAggregate.t()) :: :ok
  @callback list_transactions(fields :: list()) :: Enumerable.t()
  @callback list_io_transactions(fields :: list()) :: Enumerable.t()
  @callback add_last_transaction_address(binary(), binary(), DateTime.t()) :: :ok
  @callback list_last_transaction_addresses() :: Enumerable.t()
  @callback stream_chain(binary(), list()) :: Enumerable.t() | list(Transaction.t())

  @callback chain_size(address :: binary()) :: non_neg_integer()
  @callback list_transactions_by_type(type :: Transaction.transaction_type(), fields :: list()) ::
              Enumerable.t()
  @callback count_transactions_by_type(type :: Transaction.transaction_type()) ::
              non_neg_integer()

  @callback list_addresses_by_type(Transaction.transaction_type()) ::
              Enumerable.t() | list(binary())
  @callback list_chain_addresses(binary()) ::
              Enumerable.t() | list({binary(), DateTime.t()})
  @callback list_chain_public_keys(binary(), DateTime.t()) ::
              Enumerable.t() | list({binary(), DateTime.t()})
  @callback list_genesis_addresses() :: Enumerable.t()

  @callback get_last_chain_address_stored(genesis_address :: Crypto.prepended_hash()) ::
              Crypto.prepended_hash() | nil
  @callback get_last_chain_address(binary()) :: {binary(), DateTime.t()}
  @callback get_last_chain_address(binary(), DateTime.t()) :: {binary(), DateTime.t()}
  @callback get_genesis_address(address :: Crypto.prepended_hash()) ::
              genesis_address :: Crypto.prepended_hash()
  @callback find_genesis_address(address :: Crypto.prepended_hash()) ::
              {:ok, genesis_address :: Crypto.prepended_hash()} | {:error, :not_found}
  @callback get_first_public_key(Crypto.key()) :: binary()
  @callback register_stats(DateTime.t(), float(), non_neg_integer(), non_neg_integer()) :: :ok
  @callback get_latest_tps() :: float()
  @callback get_latest_burned_fees() :: non_neg_integer()
  @callback get_nb_transactions() :: non_neg_integer()

  @callback transaction_exists?(binary(), storage_type()) :: boolean()

  @callback register_p2p_summary(
              list(
                {node_public_key :: Crypto.key(), available? :: boolean(),
                 average_availability :: float(), availability_update :: DateTime.t(),
                 network_patch :: binary()}
              )
            ) :: :ok

  @callback get_last_p2p_summaries() ::
              list(
                {node_public_key :: Crypto.key(), available? :: boolean(),
                 average_availability :: float(), availability_update :: DateTime.t(),
                 network_patch :: String.t() | nil}
              )

  @callback get_bootstrap_info(key :: String.t()) :: String.t() | nil
  @callback set_bootstrap_info(key :: String.t(), value :: String.t()) :: :ok

  @callback list_first_addresses() :: Enumerable.t() | list(Crypto.prepended_hash())

  @callback filepath() :: binary()
end
