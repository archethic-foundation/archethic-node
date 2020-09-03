defmodule UnirisWeb.GraphQLSchema do
  @moduledoc false

  use Absinthe.Schema

  alias Uniris.Storage
  alias Uniris.Transaction

  alias __MODULE__.TransactionType

  import_types(TransactionType)

  query do
    field :transaction, :transaction do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        with {:ok, tx} <- Uniris.search_transaction(address) do
          {:ok, Transaction.to_map(tx)}
        end
      end)
    end

    field :last_transaction, :transaction do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        with {:ok, tx} <- Uniris.get_last_transaction(address) do
          {:ok, Transaction.to_map(tx)}
        end
      end)
    end

    field :transactions, list_of(:transaction) do
      resolve(fn _, _ ->
        {:ok,
         Storage.list_transactions()
         |> Enum.reject(&(&1.type == :beacon))
         |> Enum.map(&Transaction.to_map/1)}
      end)
    end

    field :transaction_chain, list_of(:transaction) do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        chain =
          Uniris.get_transaction_chain(address)
          |> Enum.map(&Transaction.to_map/1)

        {:ok, chain}
      end)
    end
  end

  subscription do
    field :new_transaction, :transaction do
      config(fn _args, _info ->
        {:ok, topic: "*"}
      end)

      resolve(fn address, _, _ ->
        case Uniris.search_transaction(address) do
          {:ok, tx} ->
            {:ok, Transaction.to_map(tx)}
        end
      end)
    end

    field :acknowledge_storage, :transaction do
      arg(:address, non_null(:address))

      config(fn args, _info ->
        {:ok, topic: args.address}
      end)

      resolve(fn address, _, _ ->
        {:ok, tx} = Uniris.search_transaction(address)
        {:ok, Transaction.to_map(tx)}
      end)
    end
  end
end
