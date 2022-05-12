defmodule ArchethicWeb.GraphQLSchema do
  @moduledoc false

  use Absinthe.Schema

  alias __MODULE__.DateTimeType
  alias __MODULE__.HexType
  alias __MODULE__.P2PType
  alias __MODULE__.Resolver
  alias __MODULE__.SharedSecretsType
  alias __MODULE__.TransactionType
  alias __MODULE__.PageType
  alias __MODULE__.TransactionAttestation

  import_types(HexType)
  import_types(DateTimeType)
  import_types(TransactionType)
  import_types(SharedSecretsType)
  import_types(P2PType)
  import_types(TransactionAttestation)
  import_types(PageType)

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
      arg(:paging_address, :address)

      resolve(fn args = %{address: address}, _ ->
        paging_address = Map.get(args, :paging_address)
        Resolver.transaction_chain_by_paging_address(address, paging_address)
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

    @desc """
    Query the network to list the transaction on the type
    """
    field :network_transactions, list_of(:transaction) do
      arg(:type, :transaction_type)
      arg(:page, :page)

      resolve(fn args, _ ->
        type = Map.get(args, :type)
        page = Map.get(args, :page, 1)
        {:ok, Resolver.network_transactions(type, page)}
      end)
    end
  end

  subscription do
    @desc """
    Subscribe to be notified when a transaction is stored (if acted as welcome node)
    """
    field :transaction_confirmed, :transaction_attestation do
      arg(:address, non_null(:address))

      config(fn args, _info ->
        {:ok, topic: args.address}
      end)
    end
  end
end
