defmodule Uniris.OracleChain.MemTableLoader do
  @moduledoc false

  alias Uniris.OracleChain.MemTable

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData

  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    TransactionChain.list_transactions_by_type(:oracle_summary, [
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
        type: :oracle,
        data: %TransactionData{content: content},
        validation_stamp: %ValidationStamp{timestamp: timestamp}
      }) do
    content
    |> Jason.decode!()
    |> Enum.each(fn {service, data} ->
      MemTable.add_oracle_data(service, data, timestamp)
    end)
  end

  def load_transaction(%Transaction{
        type: :oracle_summary,
        data: %TransactionData{content: content}
      }) do
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
