defmodule ArchethicWeb.API.GraphQL.Schema do
  @moduledoc false

  use Absinthe.Schema

  alias __MODULE__.SortOrderEnum
  alias __MODULE__.DateTimeType
  alias __MODULE__.HexType
  alias __MODULE__.P2PType
  alias __MODULE__.Resolver
  alias __MODULE__.SharedSecretsType
  alias __MODULE__.TransactionType
  alias __MODULE__.IntegerType
  alias __MODULE__.AddressType
  alias __MODULE__.ContentType
  alias __MODULE__.HashType
  alias __MODULE__.PublicKeyType
  alias __MODULE__.TransactionAttestation
  alias __MODULE__.TransactionError
  alias __MODULE__.OracleData
  alias __MODULE__.Version
  alias __MODULE__.BeaconChainSummary

  import_types(SortOrderEnum)
  import_types(AddressType)
  import_types(ContentType)
  import_types(HashType)
  import_types(PublicKeyType)
  import_types(HexType)
  import_types(DateTimeType)
  import_types(TransactionType)
  import_types(SharedSecretsType)
  import_types(P2PType)
  import_types(TransactionAttestation)
  import_types(TransactionError)
  import_types(IntegerType)
  import_types(OracleData)
  import_types(Version)
  import_types(BeaconChainSummary)

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
    Query the network to find the genesis address of a transaction
    """
    field :genesis_address, :address do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        Resolver.get_genesis_address(address)
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
      arg(:page, :pos_integer)

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
      arg(:from, :timestamp)
      arg(:order, :sort_order)

      resolve(fn args = %{address: address}, _ ->
        paging_address = Map.get(args, :paging_address)
        from = Map.get(args, :from)
        order = Map.get(args, :order, :asc)

        Resolver.transaction_chain_by_paging_address(address, paging_address, from, order)
      end)
    end

    @desc """
    Query the network to find a balance from an address coming from the latest transaction on the chain
    """
    field :balance, :balance do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        Resolver.get_balance(address)
      end)
    end

    @desc """
    Query the network to find a token's data
    """
    field :token, :token do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        Resolver.get_token(address)
      end)
    end

    @desc """
    Query the network to list the transaction inputs from an address
    """
    field :transaction_inputs, list_of(:transaction_input) do
      arg(:address, non_null(:address))
      arg(:paging_offset, :non_neg_integer)
      arg(:limit, :pos_integer)

      resolve(fn args = %{address: address}, _ ->
        paging_offset = Map.get(args, :paging_offset, 0)
        limit = Map.get(args, :limit, 0)
        Resolver.get_inputs(address, paging_offset, limit)
      end)
    end

    @desc """
    Query the network to get the storage nonce public key
    """
    field :shared_secrets, :shared_secrets do
      resolve(fn _, _ ->
        {:ok, Resolver.shared_secrets()}
      end)
    end

    @desc """
    List all the nodes registered in the network
    """
    field :nodes, list_of(:node) do
      resolve(fn _, _ ->
        {:ok, Resolver.nodes()}
      end)
    end

    @desc """
    List the nearest endpoints nodes from the client's IP
    """
    field :nearest_endpoints, list_of(:endpoint) do
      resolve(fn _, %{context: %{ip: ip}} ->
        {:ok, Resolver.nearest_endpoints(ip)}
      end)
    end

    @desc """
    Query the network to list the transaction on the type
    """
    field :network_transactions, list_of(:transaction) do
      arg(:type, non_null(:transaction_type))
      arg(:page, :pos_integer)

      resolve(fn args, _ ->
        type = Map.get(args, :type)
        page = Map.get(args, :page, 1)
        {:ok, Resolver.network_transactions(type, page)}
      end)
    end

    @desc """
    Query the network to get the value of an oracle at a specific time or the last value
    """
    field :oracle_data, :oracle_data do
      arg(:timestamp, :timestamp)

      resolve(fn args, _ ->
        datetime = Map.get(args, :timestamp, DateTime.utc_now())

        case Archethic.OracleChain.get_oracle_data("uco", datetime) do
          {:ok, %{"eur" => eur, "usd" => usd}, datetime} ->
            {:ok, %{services: %{uco: %{eur: eur, usd: usd}}, timestamp: datetime}}

          {:error, :not_found} ->
            {:error, "Not data found at this date"}
        end
      end)
    end

    @desc """
    Query the network to get the value of the summary of beacon chain at a specific time or the last value
    """
    field :beacon_chain_summary, :beacon_chain_summary do
      arg(:timestamp, :timestamp)

      resolve(fn args, _ ->
        datetime = Map.get(args, :timestamp, DateTime.utc_now())

        Resolver.beacon_chain_summary(datetime)
      end)
    end

    @desc """
    List protocol, transaction and code versions
    """
    field :version, :version do
      resolve(fn _, _ ->
        {:ok, Resolver.get_version()}
      end)
    end

    @desc """
    Query the network to retrieve the unspent output of a chain
    (address should be the genesis address of the chain)
    """
    field :chain_unspent_outputs, list_of(:unspent_output) do
      arg(:address, non_null(:address))
      arg(:paging_offset, :non_neg_integer)
      arg(:limit, :pos_integer)

      resolve(fn args = %{address: address}, _ ->
        paging_offset = Map.get(args, :paging_offset, 0)
        limit = Map.get(args, :limit, 0)
        Resolver.get_genesis_unspent_outputs(address, paging_offset, limit)
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

    @desc """
    Subscribe to be notified when a transaction is on error
    """
    field :transaction_error, :transaction_error do
      arg(:address, non_null(:address))

      config(fn args, _info ->
        {:ok, topic: args.address}
      end)
    end

    @desc """
    Subscribe to be notified when a new oracle data is stored
    """
    field :oracle_update, :oracle_data do
      config(fn _args, _info ->
        {:ok, topic: "oracle-topic"}
      end)

      resolve(fn %{timestamp: timestamp, services: %{"uco" => %{"eur" => eur, "usd" => usd}}},
                 _,
                 _ ->
        {:ok,
         %{
           timestamp: timestamp,
           services: %{
             uco: %{
               eur: eur,
               usd: usd
             }
           }
         }}
      end)
    end
  end
end
