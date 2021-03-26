defmodule Uniris.DBImpl do
  @moduledoc false

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Summary

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

  @callback register_beacon_summary(Summary.t()) :: :ok
  @callback register_beacon_slot(Slot.t()) :: :ok
  @callback get_beacon_summary(subset :: binary(), date :: DateTime.t()) ::
              {:ok, Summary.t()} | {:error, :not_found}
  @callback get_beacon_slot(subset :: binary(), date :: DateTime.t()) ::
              {:ok, Slot.t()} | {:error, :not_found}
  @callback get_beacon_slots(subset :: binary(), from_date :: DateTime.t()) :: Enumerable.t()
end
