defmodule Uniris.Interpreter.TransactionLoader do
  @moduledoc false

  alias Uniris.Interpreter

  alias Uniris.PubSub
  alias Uniris.Storage

  alias Uniris.Transaction
  alias Uniris.TransactionData

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    Enum.each(Storage.list_transactions(), &load_transaction/1)
    PubSub.register_to_new_transaction()
    {:ok, []}
  end

  def handle_info({:new_transaction, tx = %Transaction{}}, state) do
    load_transaction(tx)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp load_transaction(tx = %Transaction{data: %TransactionData{code: code}}) when code != "" do
    Interpreter.new_contract(tx)
  end

  defp load_transaction(_), do: :ok
end
