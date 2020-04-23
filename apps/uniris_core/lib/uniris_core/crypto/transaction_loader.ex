defmodule UnirisCore.Crypto.TransactionLoader do
  @moduledoc false

  alias UnirisCore.Transaction
  alias UnirisCore.Storage
  alias UnirisCore.PubSub
  alias UnirisCore.Crypto

  require Logger

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    Storage.node_transactions()
    |> Enum.each(&load_transaction/1)

    PubSub.register_to_new_transaction()

    {:ok, []}
  end

  def handle_info({:new_transaction, tx = %Transaction{}}, state) do
    load_transaction(tx)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp load_transaction(%Transaction{
         type: :node,
         previous_public_key: previous_public_key
       }) do
    previous_address = Crypto.hash(previous_public_key)

    case Storage.get_transaction(previous_address) do
      {:ok, %Transaction{previous_public_key: last_public_key}} ->
        if Crypto.node_public_key() == last_public_key do
          Crypto.increment_number_of_generate_node_keys()
          Logger.info("Node key index incremented")
        end

      {:error, :transaction_not_exists} ->
        if Crypto.node_public_key() == previous_public_key do
          Crypto.increment_number_of_generate_node_keys()
          Logger.info("Node key index incremented")
        end
    end
  end

  defp load_transaction(_tx), do: :ok
end
