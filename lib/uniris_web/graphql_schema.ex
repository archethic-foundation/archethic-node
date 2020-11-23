defmodule UnirisWeb.GraphQLSchema do
  @moduledoc false

  use Absinthe.Schema

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionInput

  alias __MODULE__.TransactionType

  import_types(TransactionType)

  query do
    @desc """
    Query the network to find a transaction
    """
    field :transaction, :transaction do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        with {:ok, tx} <- Uniris.search_transaction(address) do
          {:ok, Transaction.to_map(tx)}
        end
      end)
    end

    @desc """
    Query the network to find the last transaction from an address
    """
    field :last_transaction, :transaction do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        with {:ok, tx} <- Uniris.get_last_transaction(address) do
          {:ok, Transaction.to_map(tx)}
        end
      end)
    end

    @desc """
    Query the network to find all the transactions locally stored
    """
    field :transactions, list_of(:transaction) do
      resolve(fn _, _ ->
        {:ok,
         TransactionChain.list_all()
         |> Stream.reject(&(&1.type == :beacon))
         |> Stream.map(&Transaction.to_map/1)}
      end)
    end

    @desc """
    Query the network to find a transaction chain
    """
    field :transaction_chain, list_of(:transaction) do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        chain =
          Uniris.get_transaction_chain(address)
          |> Enum.map(&Transaction.to_map/1)

        {:ok, chain}
      end)
    end

    @desc """
    Query the network to find a balance from an address
    """
    field :balance, :balance do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        %{uco: uco, nft: nft_balances} = Uniris.get_balance(address)

        res = %{
          uco: uco,
          nft:
            Enum.map(nft_balances, fn {address, amount} ->
              %{
                address: address,
                amount: amount
              }
            end)
        }

        {:ok, res}
      end)
    end

    @desc """
    Query the network to list the transaction inputs from an address
    """
    field :transaction_inputs, list_of(:input) do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        inputs = Uniris.get_transaction_inputs(address)
        {:ok, Enum.map(inputs, &TransactionInput.to_map/1)}
      end)
    end
  end

  subscription do
    @desc """
    Subscribe for any new transaction stored locally
    """
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

    @desc """
    Subscribe to be notified when a transaction is stored (if acted as welcome node)
    """
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
