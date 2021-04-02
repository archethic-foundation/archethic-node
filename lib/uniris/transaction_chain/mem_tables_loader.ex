defmodule Uniris.TransactionChain.MemTablesLoader do
  @moduledoc false

  use GenServer

  alias Uniris.Contracts.Contract
  alias Uniris.Contracts.Contract.Conditions

  alias Uniris.DB

  alias Uniris.TransactionChain.MemTables.PendingLedger
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  require Logger

  @query_fields [:address, :type, :timestamp, :previous_public_key, data: [:code]]

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    DB.list_transactions(@query_fields)
    |> Stream.each(&load_transaction/1)
    |> Stream.run()

    {:ok, []}
  end

  @doc """
  Ingest the transaction into the memory tables
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(tx = %Transaction{address: tx_address, type: tx_type}) do
    :ok = handle_pending_transaction(tx)
    :ok = handle_transaction_recipients(tx)

    Logger.debug("Loaded into in memory chain tables",
      transaction: "#{tx_type}@#{Base.encode16(tx_address)}"
    )
  end

  defp handle_pending_transaction(%Transaction{address: address, type: :code_proposal}) do
    PendingLedger.add_address(address)
  end

  defp handle_pending_transaction(%Transaction{data: %TransactionData{code: ""}}), do: :ok

  defp handle_pending_transaction(tx = %Transaction{address: address}) do
    # TODO: improve the criteria of pending detection
    case Contract.from_transaction!(tx) do
      %Contract{conditions: %Conditions{transaction: nil}} ->
        :ok

      _ ->
        PendingLedger.add_address(address)
    end
  end

  defp handle_transaction_recipients(%Transaction{
         address: address,
         data: %TransactionData{recipients: recipients}
       }) do
    case recipients do
      [] ->
        :ok

      _ ->
        Enum.each(recipients, &PendingLedger.add_signature(&1, address))
    end
  end
end
