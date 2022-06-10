defmodule Archethic.TransactionChain.MemTablesLoader do
  @moduledoc false

  use GenServer

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.Conditions

  alias Archethic.DB

  alias Archethic.TransactionChain.MemTables.PendingLedger
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  require Logger

  @query_fields [
    :address,
    :type,
    :previous_public_key,
    data: [:code]
  ]

  @excluded_types [
    :node,
    :node_shared_secrets,
    :oracle,
    :oracle_summary,
    :beacon,
    :beacon_summary,
    :node_rewards,
    :origin
  ]

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    DB.list_transactions(@query_fields)
    |> Stream.reject(&(&1.type in @excluded_types))
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

    Logger.info("Loaded into in memory transactionchain tables",
      transaction_address: Base.encode16(tx_address),
      transaction_type: tx_type
    )
  end

  defp handle_pending_transaction(%Transaction{address: address, type: :code_proposal}) do
    PendingLedger.add_address(address)
  end

  defp handle_pending_transaction(%Transaction{data: %TransactionData{code: ""}}), do: :ok

  defp handle_pending_transaction(tx = %Transaction{address: address}) do
    %Contract{conditions: %{transaction: transaction_conditions}} = Contract.from_transaction!(tx)

    # TODO: improve the criteria of pending detection
    if Conditions.empty?(transaction_conditions) do
      :ok
    else
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
