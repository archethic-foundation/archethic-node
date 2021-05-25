defmodule Uniris.DBImpl do
  @moduledoc false

  alias Uniris.Crypto

  alias Uniris.TransactionChain.Transaction

  @callback migrate() :: :ok
  @callback get_transaction(address :: binary(), fields :: list()) ::
              {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  @callback get_transaction_chain(binary(), fields :: list()) :: Enumerable.t()
  @callback write_transaction(Transaction.t()) :: :ok
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
end
