defmodule Uniris.OracleChain.MemTableLoader do
  @moduledoc false

  alias Uniris.OracleChain.MemTable

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    TransactionChain.list_transactions_by_type(:oracle_summary, [:type, data: [:content]])
    |> Stream.each(&load_transaction/1)
    |> Stream.run()

    {:ok, []}
  end

  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{type: :oracle, data: %TransactionData{content: content}}) do
    data = Jason.decode!(content) |> Map.get("data")
    Enum.each(data, &load_by_service/1)
  end

  def load_transaction(%Transaction{
        type: :oracle_summary,
        data: %TransactionData{content: content}
      }) do
    content
    |> Jason.decode!()
    |> Map.get("data")
    |> Enum.each(fn {_timestamp, data} ->
      Enum.each(data, &load_by_service/1)
    end)
  end

  defp load_by_service({"uco", prices}) do
    MemTable.add_oracle_data("uco", prices)
  end
end
