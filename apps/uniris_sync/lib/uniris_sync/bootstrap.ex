defmodule UnirisSync.Bootstrap do
  @moduledoc false

  use Task

  require Logger

  alias UnirisP2P, as: P2P
  alias UnirisP2P.Node
  alias UnirisCrypto, as: Crypto
  alias UnirisChain.Transaction
  alias UnirisSharedSecrets, as: SharedSecrets
  alias UnirisSync, as: Sync

  def start_link(opts) do
    ip = Keyword.get(opts, :ip)
    port = Keyword.get(opts, :port)
    Task.start_link(__MODULE__, :run, [ip, port])
  end

  @doc """
  Run the node bootstraping process to setup the node
  and retrieve the necessary items to start the synchronization
  """
  def run(ip_address, port) do
    Logger.info("Bootstraping starting")

    first_public_key = Crypto.node_public_key(0)
    last_public_key = Crypto.node_public_key()

    node = create_local_node(ip_address, port, first_public_key, last_public_key)

    case P2P.list_seeds() do
      # Being the first seed no need to retrieve from other
      # But initialize the shared secrets
      [%Node{first_public_key: seed_key} | _] when seed_key == first_public_key ->
        initialize_first_node(node)

      previous_seeds ->
        initialize_node(node, previous_seeds)
    end
  end

  @doc """
  Create a new node instance by geolooking the ip address to retrieve the geopatch
  and add the node the P2P view
  """
  def create_local_node(ip_address, port, first_public_key, last_public_key) do
    {:ok, ip} = :inet.parse_address(String.to_charlist(ip_address))

    self = %Node{
      ip: ip,
      port: port,
      first_public_key: first_public_key,
      last_public_key: last_public_key
    }

    :ok = P2P.add_node(self)
    :ok = P2P.connect_node(self)

    {:ok, node} = P2P.node_info(first_public_key)

    Logger.info("Local node added to the P2P view")
    node
  end

  @doc """
  Build the first node shared secret transaction and autovalidate it as well as the node transaction
  """
  def initialize_first_node(node) do
    # Authorize the first node as it will hold the daily nonce
    Node.authorize(node.first_public_key)

    # Create the first transaction on the node shared secrets
    init_shared_secrets_chain()

    update_node_chain(node, {127, 0, 0, 1})
  end

  defp init_shared_secrets_chain() do
    transaction_seed = :crypto.strong_rand_bytes(32)

    shared_secret_tx =
      %Transaction{data: %{keys: %{authorized_keys: encrypted_keys, secret: secret}}} =
      SharedSecrets.new_shared_secrets_transaction(transaction_seed)

    # Retrieve and load the seeds generated used for the auto validation of the transaction
    # (as first node)
    aes_key = Crypto.ec_decrypt_with_node_key!(Map.get(encrypted_keys, Crypto.node_public_key()))

    %{
      daily_nonce_seed: daily_nonce_seed,
      storage_nonce_seed: storage_nonce_seed
    } = Crypto.aes_decrypt!(secret, aes_key)

    Crypto.set_daily_nonce(daily_nonce_seed)
    Crypto.set_storage_nonce(storage_nonce_seed)

    UnirisSync.subscribe_to(shared_secret_tx.address)
    P2P.send_message({127, 0, 0, 1}, {:new_transaction, shared_secret_tx})

    receive do
      {:acknowledge_storage, _} ->
        Logger.info("Shared secret transaction stored")
    end
  end

  defp update_node_chain(node = %Node{}, remote_node) do
    node_tx = create_node_transaction(node)
    UnirisSync.subscribe_to(node_tx.address)
    P2P.send_message(remote_node, {:new_transaction, node_tx})

    receive do
      {:acknowledge_storage, _} ->
        Logger.info("Node transaction stored")
    end
  end

  @doc """
  Create new node transaction from the seed, node information and the number of previous node transactions
  """
  def create_node_transaction(%Node{
        ip: ip,
        port: port,
        first_public_key: first_public_key,
        last_public_key: last_public_key
      }) do
    Transaction.from_node_seed(
      :node,
      %Transaction.Data{
        content: """
          ip: #{ip |> Tuple.to_list() |> Enum.join(".")}
          port: #{port}
          first_public_key: #{first_public_key |> Base.encode16()}
          last_public_key: #{last_public_key |> Base.encode16()}
        """
      }
    )
  end

  @doc """
  Retrieve initialization data from the seeds, update the new seeds, add the closest nodes to the P2P view
  and send the transaction to  the closest nodes.

  The storage nonce as well as the origin keys are loaded into the Crypto module
  """
  def initialize_node(node = %Node{}, previous_seeds) do
    previous_seeds
    |> Enum.reject(fn n -> n in P2P.list_nodes() end)
    |> Enum.each(fn n ->
      Logger.info("Adding the seed #{n.last_public_key |> Base.encode16()} to the P2P view")
      P2P.add_node(n)
      P2P.connect_node(n)
    end)

    {new_seeds, closest_nodes, origin_keys_seeds, storage_nonce_seed, authorized_nodes} =
      request_init_data(previous_seeds, node.geo_patch)

    (new_seeds ++ closest_nodes)
    |> Enum.dedup_by(fn %Node{first_public_key: key} -> key end)
    |> Enum.reject(&(&1.last_public_key == Crypto.node_public_key()))
    |> Enum.each(fn n ->
      if n.last_public_key in authorized_nodes do
        Node.authorize(n)
        Logger.info("Authorize node #{n.last_public_key |> Base.encode16()}")
      else
        P2P.add_node(n)
        P2P.connect_node(n)
        Node.authorize(n)
        Logger.info("Add node #{n.last_public_key |> Base.encode16()} to the P2P view")
      end
    end)

    Crypto.set_storage_nonce(storage_nonce_seed)
    Logger.info("Storage nonce loaded")

    Enum.each(origin_keys_seeds, &Crypto.add_origin_seed(&1))
    Logger.info("Origin seeds loaded")

    update_node_chain(node, Enum.random(new_seeds))
  end

  @doc """
  Request the innitial data to start to work on the network
  including the closest nodes, the new seeds (for the a later reboostrap)
  the origin key seeds and storage nonce encrypted with the node key
  """
  def request_init_data(previous_seeds, geo_patch) do
    Logger.info("Request new seeds and closest nodes")

    [
      new_seeds,
      closest_nodes,
      %{
        origin_keys_seeds: origin_keys_seeds_encrypted,
        storage_nonce_seed: storage_nonce_seed_encrypted,
        authorized_nodes: authorized_nodes
      }
    ] =
      P2P.send_message(Enum.random(previous_seeds), [
        :new_seeds,
        {:closest_nodes, geo_patch},
        {:bootstrap_crypto_seeds, Crypto.node_public_key()}
      ])

    origin_keys_seeds = Crypto.ec_decrypt_with_node_key!(origin_keys_seeds_encrypted)
    storage_nonce_seed = Crypto.ec_decrypt_with_node_key!(storage_nonce_seed_encrypted)

    {new_seeds, closest_nodes, origin_keys_seeds, storage_nonce_seed, authorized_nodes}
  end
end
