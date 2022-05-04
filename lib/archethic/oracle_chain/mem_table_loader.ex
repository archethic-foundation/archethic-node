defmodule Archethic.OracleChain.MemTableLoader do
  @moduledoc false

  alias Archethic.OracleChain.MemTable

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  use GenServer

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    TransactionChain.list_transactions_by_type(:oracle_summary, [
      :address,
      :type,
      data: [:content],
      validation_stamp: [:timestamp]
    ])
    |> Stream.each(&load_transaction/1)
    |> Stream.run()

    {:ok, []}
  end

  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{
        address: address,
        type: :oracle,
        data: %TransactionData{content: content},
        validation_stamp: %ValidationStamp{timestamp: timestamp}
      }) do
    Logger.info("Load transaction into oracle chain mem table",
      transaction_address: Base.encode16(address),
      transaction_type: :oracle
    )

    content
    |> Jason.decode!()
    |> Enum.each(fn {service, data} ->
      MemTable.add_oracle_data(service, data, timestamp)
    end)
  end

  def load_transaction(%Transaction{
        address: address,
        type: :oracle_summary,
        data: %TransactionData{content: content}
      }) do
    Logger.info("Load transaction into oracle chain mem table",
      transaction_address: Base.encode16(address),
      transaction_type: :oracle_summary
    )

    content
    |> Jason.decode!()
    |> Enum.each(fn {timestamp, aggregated_data} ->
      Enum.each(aggregated_data, fn {service, data} ->
        {timestamp, _} = Integer.parse(timestamp)
        MemTable.add_oracle_data(service, data, DateTime.from_unix!(timestamp))
      end)
    end)
  end
end
