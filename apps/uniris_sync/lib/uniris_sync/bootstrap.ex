defmodule UnirisSync.Bootstrap do
  @moduledoc false

  use Task

  require Logger

  alias UnirisP2P, as: P2P
  alias UnirisP2P.Node
  alias UnirisCrypto, as: Crypto
  alias UnirisChain.Transaction
  alias UnirisSharedSecrets, as: SharedSecrets
  alias __MODULE__.IPLookup
  alias UnirisSync.TransactionLoader

  alias UnirisChain, as: Chain

  def start_link(opts) do
    port = Keyword.get(opts, :port)
    Task.start_link(__MODULE__, :run, [port])
  end

  @doc """
  Run the node bootstraping process to setup the node
  and retrieve the necessary items to start the synchronization
  """
  def run(port) do
    Logger.info("Bootstraping starting")

    TransactionLoader.preload_transactions()
    Logger.info("Preload stored transactions")


    first_public_key = Crypto.node_public_key(0)
    last_public_key = Crypto.node_public_key()

    ip = IPLookup.get_public_ip()
    node = create_local_node(ip, port, first_public_key, last_public_key)

    case UnirisChain.get_last_node_shared_secrets_transaction() do
      {:error, :transaction_not_exists} ->
        initialize_first_node(node)
      _ ->
        initialize_node(node, P2P.list_seeds())
    end
  end

  @doc """
  Create a new node instance by geolooking the ip address to retrieve the geopatch
  and add the node the P2P view
  """
  def create_local_node(ip, port, first_public_key, last_public_key) do
    self = %Node{
      ip: ip,
      port: port,
      first_public_key: first_public_key,
      last_public_key: last_public_key
    }

    :ok = P2P.add_node(self)

    {:ok, node} = P2P.node_info(first_public_key)

    Logger.info("Local node added to the P2P view")
    node
  end

  @doc """
  Build the first node shared secret transaction and autovalidate it as well as the node transaction
  """
  def initialize_first_node(node) do
    # Create the first transaction on the node shared secrets
    init_shared_secrets_chain()
    update_node_chain(node)
  end

  defp init_shared_secrets_chain() do
    Logger.debug("Init node shared secrets")
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

    {:ok, pow} = UnirisValidation.DefaultImpl.ProofOfWork.run(shared_secret_tx)
    poi = UnirisValidation.DefaultImpl.ProofOfIntegrity.from_transaction(shared_secret_tx)
    ledger_movements = %Transaction.ValidationStamp.LedgerMovements{}
    node_movements = %Transaction.ValidationStamp.NodeMovements{
      rewards: UnirisValidation.DefaultImpl.Reward.distribute_fee(0, Crypto.node_public_key(), Crypto.node_public_key(), [Crypto.node_public_key()], []),
      fee: 0
    }

    stamp = Transaction.ValidationStamp.new(pow, poi, ledger_movements, node_movements)
    cross_stamp = UnirisValidation.DefaultImpl.Stamp.create_cross_validation_stamp(stamp, [], Crypto.node_public_key())

    [%{shared_secret_tx | validation_stamp: stamp, cross_validation_stamps: [cross_stamp]}]
    |> Chain.store_transaction_chain()

    UnirisSync.add_transaction_to_beacon(shared_secret_tx.address, shared_secret_tx.timestamp)

    TransactionLoader.new_transaction(shared_secret_tx)
  end

  defp update_node_chain(node) do
    node_tx = create_node_transaction(node)
    {:ok, pow} = UnirisValidation.DefaultImpl.ProofOfWork.run(node_tx)
    poi = UnirisValidation.DefaultImpl.ProofOfIntegrity.from_transaction(node_tx)
    ledger_movements = %Transaction.ValidationStamp.LedgerMovements{}
    node_movements = %Transaction.ValidationStamp.NodeMovements{
      rewards: UnirisValidation.DefaultImpl.Reward.distribute_fee(0, Crypto.node_public_key(), Crypto.node_public_key(), [Crypto.node_public_key()], []),
      fee: 0
    }

    stamp = Transaction.ValidationStamp.new(pow, poi, ledger_movements, node_movements)
    cross_stamp = UnirisValidation.DefaultImpl.Stamp.create_cross_validation_stamp(stamp, [], Crypto.node_public_key())

    [%{node_tx | validation_stamp: stamp, cross_validation_stamps: [cross_stamp]}]
    |> Chain.store_transaction_chain()

    UnirisSync.add_transaction_to_beacon(node_tx.address, node_tx.timestamp)

    TransactionLoader.new_transaction(node_tx)
  end

  defp update_node_chain(node = %Node{}, remote_node) do
    Logger.debug("Update node chain...")
    node_tx = create_node_transaction(node)
    P2P.send_message(remote_node, {:new_transaction, node_tx})
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
      Logger.debug("Adding the seed #{n.last_public_key |> Base.encode16()} to the P2P view")
      P2P.add_node(n)
      P2P.connect_node(n)
    end)

    {new_seeds, closest_nodes, origin_keys_seeds, storage_nonce_seed} =
      request_init_data(previous_seeds, node.geo_patch)

    (new_seeds ++ closest_nodes)
    |> Enum.dedup_by(fn %Node{first_public_key: key} -> key end)
    |> Enum.reject(&(&1.last_public_key == Crypto.node_public_key()))
    |> Enum.each(fn n ->
      P2P.add_node(n)
      P2P.connect_node(n)
      Logger.debug("Add node #{n.last_public_key |> Base.encode16()} to the P2P view")
    end)

    Crypto.set_storage_nonce(storage_nonce_seed)
    Logger.debug("Storage nonce loaded")

    Enum.each(origin_keys_seeds, &Crypto.add_origin_seed(&1))
    Logger.debug("Origin seeds loaded")

    update_node_chain(node, Enum.random(new_seeds))
  end

  @doc """
  Request the innitial data to start to work on the network
  including the closest nodes, the new seeds (for the a later reboostrap)
  the origin key seeds and storage nonce encrypted with the node key
  """
  def request_init_data(previous_seeds, geo_patch) do
    Logger.debug("Request new seeds and closest nodes")

    [
      new_seeds,
      closest_nodes,
      %{
        origin_keys_seeds: origin_keys_seeds_encrypted,
        storage_nonce_seed: storage_nonce_seed_encrypted
      }
    ] =
      P2P.send_message(Enum.random(previous_seeds), [
        :new_seeds,
        {:closest_nodes, geo_patch},
        {:bootstrap_crypto_seeds, Crypto.node_public_key()}
      ])

    origin_keys_seeds = Crypto.ec_decrypt_with_node_key!(origin_keys_seeds_encrypted)
    storage_nonce_seed = Crypto.ec_decrypt_with_node_key!(storage_nonce_seed_encrypted)

    {new_seeds, closest_nodes, origin_keys_seeds, storage_nonce_seed}
  end
end
