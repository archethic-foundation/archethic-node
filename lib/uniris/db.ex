defmodule Uniris.DB do
  @moduledoc false

  alias Uniris.Crypto

  alias __MODULE__.CassandraImpl
  alias Uniris.TransactionChain.Transaction

  use Knigge, otp_app: :uniris, default: CassandraImpl

  @callback migrate() :: :ok
  @callback get_transaction(address :: binary(), fields :: list()) ::
              {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  @callback get_transaction_chain(binary(), fields :: list()) :: Enumerable.t()
  @callback write_transaction(Transaction.t()) :: :ok
  @callback write_transaction(Transaction.t(), binary()) :: :ok
  @callback write_transaction_chain(Enumerable.t()) :: :ok
  @callback list_transactions(fields :: list()) :: Enumerable.t()
  @callback add_last_transaction_address(binary(), binary(), DateTime.t()) :: :ok
  @callback list_last_transaction_addresses() :: Enumerable.t()

  @callback chain_size(address :: binary()) :: non_neg_integer()
  @callback list_transactions_by_type(type :: Transaction.transaction_type(), fields :: list()) ::
              Enumerable.t()
  @callback count_transactions_by_type(type :: Transaction.transaction_type()) ::
              non_neg_integer()
  @callback get_last_chain_address(binary()) :: binary()
  @callback get_last_chain_address(binary(), DateTime.t()) :: binary()
  @callback get_first_chain_address(binary()) :: binary()
  @callback get_first_public_key(Crypto.key()) :: binary()

  @callback register_tps(DateTime.t(), float(), non_neg_integer()) :: :ok
  @callback get_latest_tps() :: float()
  @callback get_nb_transactions() :: non_neg_integer()

  @callback transaction_exists?(binary()) :: boolean()
end
