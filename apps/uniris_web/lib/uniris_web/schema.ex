defmodule UnirisWeb.Schema do
  @moduledoc false

  use Absinthe.Schema

  import_types __MODULE__.TransactionType

  query do
    field :transaction, :transaction do
      arg(:address, :hash)

      resolve(fn %{address: address}, _ ->
        UnirisElection.storage_nodes(address)
        |> UnirisP2P.nearest_nodes()
        |> List.first()
        |> UnirisP2P.send_message({:get_transaction, address})
      end)
    end

    field :transactions, list_of(:transaction) do
      resolve(fn _, _ ->
        {:ok, UnirisChain.list_transactions() }
      end)
    end
  end
end
