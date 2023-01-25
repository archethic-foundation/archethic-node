defmodule Archethic.DB do
  @moduledoc false

  alias Archethic.BeaconChain.Summary
  alias Archethic.BeaconChain.SummaryAggregate

  alias Archethic.Crypto

  alias __MODULE__.EmbeddedImpl
  alias __MODULE__.EmbeddedImpl.InputsWriter

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.VersionedTransactionInput

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
                paging_state: nil | binary(),
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

  @callback chain_size(address :: binary()) :: non_neg_integer()
  @callback list_transactions_by_type(type :: Transaction.transaction_type(), fields :: list()) ::
              Enumerable.t()
  @callback count_transactions_by_type(type :: Transaction.transaction_type()) ::
              non_neg_integer()

  @callback list_addresses_by_type(Transaction.transaction_type()) ::
              Enumerable.t() | list(binary())
  @callback list_chain_addresses(binary()) ::
              Enumerable.t() | list({binary(), DateTime.t()})

  @callback get_last_chain_address(binary()) :: {binary(), DateTime.t()}
  @callback get_last_chain_address(binary(), DateTime.t()) :: {binary(), DateTime.t()}
  @callback get_last_chain_public_key(binary()) :: Crypto.key()
  @callback get_last_chain_public_key(binary(), DateTime.t()) :: Crypto.key()
  @callback get_genesis_address(binary()) :: binary()
  @callback get_first_public_key(Crypto.key()) :: binary()
  @callback register_stats(DateTime.t(), float(), non_neg_integer(), non_neg_integer()) :: :ok
  @callback get_latest_tps() :: float()
  @callback get_latest_burned_fees() :: non_neg_integer()
  @callback get_nb_transactions() :: non_neg_integer()

  @callback transaction_exists?(binary(), storage_type()) :: boolean()

  @callback register_p2p_summary(list({Crypto.key(), boolean(), float(), DateTime.t()})) :: :ok

  @callback get_last_p2p_summaries() :: %{
              (node_public_key :: Crypto.key()) =>
                {available? :: boolean(), average_availability :: float()}
            }

  @callback get_bootstrap_info(key :: String.t()) :: String.t() | nil
  @callback set_bootstrap_info(key :: String.t(), value :: String.t()) :: :ok

  @callback start_inputs_writer(input_type :: InputsWriter.input_type(), address :: binary()) ::
              {:ok, pid()}
  @callback stop_inputs_writer(pid :: pid()) :: :ok
  @callback append_input(pid :: pid(), VersionedTransactionInput.t()) ::
              :ok
  @callback get_inputs(input_type :: InputsWriter.input_type(), address :: binary()) ::
              list(VersionedTransactionInput.t())

  @callback stream_first_addresses() :: Enumerable.t()
end
