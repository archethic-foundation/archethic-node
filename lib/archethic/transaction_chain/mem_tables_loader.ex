defmodule Archethic.TransactionChain.MemTablesLoader do
  @moduledoc false

  use GenServer
  @vsn Mix.Project.config()[:version]

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConditions

  alias Archethic.DB

  alias Archethic.TransactionChain.MemTables.PendingLedger
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  require Logger

  @query_fields [
    :address,
    :type,
    :previous_public_key,
    data: [:code, :recipients],
    validation_stamp: [:timestamp]
  ]

  @excluded_types [
    :node,
    :node_shared_secrets,
    :oracle,
    :oracle_summary,
    :node_rewards,
    :mint_rewards,
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
    %Contract{conditions: conditions} = Contract.from_transaction!(tx)

    # TODO: handle {:transaction, action, args_names}
    case Map.get(conditions, {:transaction, nil, nil}) do
      nil ->
        :ok

      transaction_conditions ->
        # TODO: improve the criteria of pending detection
        if ContractConditions.empty?(transaction_conditions) do
          :ok
        else
          PendingLedger.add_address(address)
        end
    end
  end

  defp handle_transaction_recipients(%Transaction{
         address: address,
         data: %TransactionData{recipients: recipients}
       }) do
    recipients
    |> Enum.map(& &1.address)
    |> Enum.each(&PendingLedger.add_signature(&1, address))
  end
end
