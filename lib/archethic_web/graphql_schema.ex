defmodule ArchEthicWeb.GraphQLSchema do
  @moduledoc false

  use Absinthe.Schema

  alias __MODULE__.DateTimeType
  alias __MODULE__.HexType
  alias __MODULE__.P2PType
  alias __MODULE__.Resolver
  alias __MODULE__.SharedSecretsType
  alias __MODULE__.TransactionType

  import_types(HexType)
  import_types(DateTimeType)
  import_types(TransactionType)
  import_types(SharedSecretsType)
  import_types(P2PType)

  query do
    @desc """
    Query the network to find a transaction
    """
    field :transaction, :transaction do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        Resolver.get_transaction(address)
      end)
    end

    @desc """
    Query the network to find the last transaction from an address
    """
    field :last_transaction, :transaction do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        Resolver.get_last_transaction(address)
      end)
    end

    @desc """
    Query the network to find all the transactions locally stored
    """
    field :transactions, list_of(:transaction) do
      arg(:page, :integer)

      resolve(fn args, _ ->
        page = Map.get(args, :page, 1)
        {:ok, Resolver.paginate_local_transactions(page)}
      end)
    end

    @desc """
    Query the network to find a transaction chain
    """
    field :transaction_chain, list_of(:transaction) do
      arg(:address, non_null(:address))
      arg(:page, :integer)

      resolve(fn args = %{address: address}, _ ->
        page = Map.get(args, :page, 1)
        Resolver.paginate_chain(address, page)
      end)
    end

    @desc """
    Query the network to find a balance from an address
    """
    field :balance, :balance do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        Resolver.get_balance(address)
      end)
    end

    @desc """
    Query the network to list the transaction inputs from an address
    """
    field :transaction_inputs, list_of(:transaction_input) do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        Resolver.get_inputs(address)
      end)
    end

    field :shared_secrets, :shared_secrets do
      resolve(fn _, _ ->
        {:ok, Resolver.shared_secrets()}
      end)
    end

    field :nodes, list_of(:node) do
      resolve(fn _, _ ->
        {:ok, Resolver.nodes()}
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
        Resolver.get_transaction(address)
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
        Resolver.get_transaction(address)
      end)
    end
  end
end
