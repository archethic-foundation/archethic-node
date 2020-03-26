defmodule UnirisSync.Bootstrap do
  @moduledoc """
  Bootstrap a node in the Uniris network

  If the first node, the first node shared transaction is created and the transactions are self validated.

  Otherwise it will retrieve the necessary items to start the synchronization and send its new transaction to the closest node.
  """
  use Task

  require Logger

  alias UnirisP2P, as: P2P
  alias UnirisP2P.Node
  alias UnirisCrypto, as: Crypto
  alias UnirisChain, as: Chain
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements
  alias UnirisChain.Transaction
  alias UnirisValidation, as: Validation
  alias UnirisSharedSecrets, as: SharedSecrets
  alias UnirisBeacon, as: Beacon
  alias UnirisPubSub, as: PubSub
  alias __MODULE__.IPLookup

  def start_link(opts) do
    port = Keyword.get(opts, :port)
    ip = IPLookup.get_ip()

    Task.start_link(__MODULE__, :run, [ip, port])
  end

  def run(ip, port) do
    Logger.info("Bootstraping starting")

    first_public_key = Crypto.node_public_key(0)
    last_public_key = Crypto.node_public_key()

    node = %Node{
      ip: ip,
      port: port,
      first_public_key: first_public_key,
      last_public_key: last_public_key
    }

    P2P.add_node(node)
    P2P.connect_node(node)

    with {:error, :transaction_not_exists} <-
           UnirisChain.get_last_node_shared_secrets_transaction(),
         [%Node{first_public_key: key}] when key == first_public_key <- P2P.list_seeds() do
      Logger.info("Network initialization...")
      init_shared_secrets_chain()
      tx = create_node_transaction(node)
      self_validation(tx)
    else
      _ ->
        Logger.info("Node initialization...")
        load_nodes_and_seeds(P2P.get_geo_patch(ip))
        update_node_chain(node)
    end
  end

  defp init_shared_secrets_chain() do
    Logger.debug("Init node shared secrets")
    transaction_seed = :crypto.strong_rand_bytes(32)

    # Create the node shared secret transaction
    shared_secret_tx =
      %Transaction{data: %{keys: %{authorized_keys: encrypted_keys, secret: secret}}} =
      SharedSecrets.new_shared_secrets_transaction(transaction_seed, [Crypto.node_public_key()])

    # Retrieve and load the seeds generated used for the auto validation of the transaction
    # (as first node)
    aes_key = Crypto.ec_decrypt_with_node_key!(Map.get(encrypted_keys, Crypto.node_public_key()))

    %{
      daily_nonce_seed: daily_nonce_seed,
      storage_nonce_seed: storage_nonce_seed
    } = Crypto.aes_decrypt!(secret, aes_key)

    Crypto.set_daily_nonce(daily_nonce_seed)
    Crypto.set_storage_nonce(storage_nonce_seed)

    self_validation(shared_secret_tx)
  end

  defp self_validation(tx = %Transaction{}) do
    {:ok, pow} = Validation.get_proof_of_work(tx)
    poi = Validation.get_proof_of_integrity([tx])
    ledger_movements = %LedgerMovements{}

    fee = Validation.get_transaction_fee(tx)

    node_movements = %NodeMovements{
      rewards:
        Validation.get_node_rewards(
          fee,
          Crypto.node_public_key(),
          Crypto.node_public_key(),
          [Crypto.node_public_key()],
          []
        ),
      fee: 0
    }

    stamp = ValidationStamp.new(pow, poi, ledger_movements, node_movements)
    cross_stamp = Validation.get_cross_validation_stamp(stamp, [])

    validated_tx = %{tx | validation_stamp: stamp, cross_validation_stamps: [cross_stamp]}
    Chain.store_transaction_chain([validated_tx])

    Beacon.add_transaction(tx.address, tx.timestamp)
    PubSub.notify_new_transaction(tx)
  end

  defp load_nodes_and_seeds(geo_patch) do
    previous_seeds = P2P.list_seeds()
    load_nodes(previous_seeds)

    {new_seeds, closest_nodes, origin_keys_seeds, storage_nonce_seed} =
      request_init_data(previous_seeds, geo_patch)

    load_nodes(new_seeds ++ closest_nodes)

    Crypto.set_storage_nonce(storage_nonce_seed)
    Logger.debug("Storage nonce loaded")

    Enum.each(origin_keys_seeds, fn seed ->
      Crypto.add_origin_seed(seed)
    end)

    Logger.debug("Origin seeds loaded")
  end

  defp create_node_transaction(%Node{
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

  defp update_node_chain(node = %Node{}) do
    Logger.debug("Update node chain...")
    tx = create_node_transaction(node)
    P2P.send_message(Enum.random(P2P.authorized_nodes()), {:new_transaction, tx})
  end

  defp load_nodes(nodes) do
    nodes
    |> Enum.reject(fn n -> n in P2P.list_nodes() end)
    |> Enum.reject(&(&1.last_public_key == Crypto.node_public_key()))
    |> Enum.each(fn n ->
      Logger.debug("Adding the node #{n.first_public_key |> Base.encode16()} to the P2P view")
      P2P.add_node(n)
      P2P.connect_node(n)
    end)
  end

  defp request_init_data(previous_seeds, geo_patch) do
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
