defmodule Archethic.Bootstrap.Sync do
  @moduledoc false

  alias Archethic.BeaconChain
  alias Archethic.Bootstrap.NetworkInit

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message.BootstrappingNodes
  alias Archethic.P2P.Message.EncryptedStorageNonce
  alias Archethic.P2P.Message.GetBootstrappingNodes
  alias Archethic.P2P.Message.GetStorageNonce
  alias Archethic.P2P.Message.NotifyEndOfNodeSync
  alias Archethic.P2P.Node

  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

  require Logger

  @out_of_sync_date_threshold Application.compile_env(:archethic, [
                                __MODULE__,
                                :out_of_sync_date_threshold
                              ])

  @genesis_daily_nonce_seed Application.compile_env!(:archethic, [
                              NetworkInit,
                              :genesis_daily_nonce_seed
                            ])

  @doc """
  Determines if network should be initialized
  """
  @spec should_initialize_network?(list(Node.t())) :: boolean()
  def should_initialize_network?([]) do
    TransactionChain.count_transactions_by_type(:node_shared_secrets) == 0
  end

  def should_initialize_network?([%Node{first_public_key: node_key} | _]) do
    node_key == Crypto.first_node_public_key() and
      TransactionChain.count_transactions_by_type(:node_shared_secrets) == 0
  end

  def should_initialize_network?(_), do: false

  @doc """
  Determines if the node requires an update
  """
  @spec require_update?(
          :inet.ip_address(),
          :inet.port_number(),
          :inet.port_number(),
          P2P.supported_transport(),
          DateTime.t() | nil
        ) :: boolean()
  def require_update?(_ip, _port, _http_port, _transport, nil), do: false

  def require_update?(ip, port, http_port, transport, last_sync_date) do
    first_node_public_key = Crypto.first_node_public_key()

    case P2P.authorized_and_available_nodes() do
      [%Node{first_public_key: ^first_node_public_key}] ->
        false

      _ ->
        diff_sync = DateTime.diff(DateTime.utc_now(), last_sync_date, :second)

        case P2P.get_node_info(first_node_public_key) do
          {:ok,
           %Node{
             ip: prev_ip,
             port: prev_port,
             http_port: prev_http_port,
             transport: prev_transport
           }}
          when ip != prev_ip or port != prev_port or http_port != prev_http_port or
                 diff_sync > @out_of_sync_date_threshold or
                 prev_transport != transport ->
            true

          _ ->
            false
        end
    end
  end

  @doc """
  Initialize the network by predefining the storage nonce, the first node transaction and the first node shared secrets and the genesis fund allocations
  """
  @spec initialize_network(Transaction.t()) :: :ok
  def initialize_network(node_tx = %Transaction{}) do
    NetworkInit.create_storage_nonce()

    secret_key = :crypto.strong_rand_bytes(32)
    encrypted_secret_key = Crypto.ec_encrypt(secret_key, Crypto.last_node_public_key())

    encrypted_daily_nonce_seed = Crypto.aes_encrypt(@genesis_daily_nonce_seed, secret_key)
    encrypted_transaction_seed = Crypto.aes_encrypt(:crypto.strong_rand_bytes(32), secret_key)
    encrypted_reward_seed = Crypto.aes_encrypt(:crypto.strong_rand_bytes(32), secret_key)

    secrets =
      <<encrypted_daily_nonce_seed::binary, encrypted_transaction_seed::binary,
        encrypted_reward_seed::binary>>

    :ok = Crypto.unwrap_secrets(secrets, encrypted_secret_key, ~U[1970-01-01 00:00:00Z])

    :ok =
      node_tx
      |> NetworkInit.self_validation()
      |> NetworkInit.self_replication()

    P2P.set_node_globally_available(Crypto.first_node_public_key(), DateTime.utc_now())
    P2P.set_node_globally_synced(Crypto.first_node_public_key())

    P2P.authorize_node(
      Crypto.last_node_public_key(),
      SharedSecrets.next_application_date(DateTime.utc_now())
    )

    NetworkInit.init_software_origin_chain()
    NetworkInit.init_node_shared_secrets_chain()
    NetworkInit.init_genesis_wallets()
    NetworkInit.init_network_reward_pool()
  end

  @doc """
  Fetch and load the nodes list
  """
  @spec connect_current_node(closest_nodes :: list(Node.t())) ::
          {:ok, list(Node.t())} | {:error, :network_issue}
  def connect_current_node(closest_nodes) do
    case P2P.fetch_nodes_list(true, closest_nodes) do
      {:ok, nodes} ->
        P2P.connect_nodes(nodes)
        Logger.info("Node list refreshed")
        {:ok, nodes}

      {:error, :network_issue} ->
        {:error, :network_issue}
    end
  end

  @doc """
  Fetch and load the storage nonce
  """
  @spec load_storage_nonce(list(Node.t())) :: :ok | {:error, :network_issue}
  def load_storage_nonce([node | rest]) do
    message = %GetStorageNonce{public_key: Crypto.last_node_public_key()}

    case P2P.send_message(node, message) do
      {:ok, %EncryptedStorageNonce{digest: encrypted_nonce}} ->
        :ok = Crypto.decrypt_and_set_storage_nonce(encrypted_nonce)
        Logger.info("Storage nonce set")

      {:error, _} ->
        load_storage_nonce(rest)
    end
  end

  def load_storage_nonce([]), do: {:error, :network_issue}

  @doc """
  Fetch the closest nodes and new bootstrapping seeds.

  The new bootstrapping seeds are loaded and flushed for the next bootstrap.

  The closest nodes and the bootstrapping seeds are loaded into the P2P view

  Returns the closest nodes
  """
  @spec get_closest_nodes_and_renew_seeds(list(Node.t()), binary()) ::
          {:ok, list(Node.t())} | {:error, :network_issue}
  def get_closest_nodes_and_renew_seeds([node | rest], patch) do
    case P2P.send_message(node, %GetBootstrappingNodes{patch: patch}) do
      {:ok,
       %BootstrappingNodes{
         closest_nodes: closest_nodes,
         new_seeds: new_seeds,
         first_enrolled_node: first_enrolled_node
       }} ->
        :ok = P2P.new_bootstrapping_seeds(new_seeds)

        case P2P.get_first_enrolled_node() do
          nil ->
            # Replace values to match P2P view on network bootstrap
            %Node{
              first_enrolled_node
              | last_update_date: ~U[2019-07-14 00:00:00Z],
                availability_update: ~U[2008-10-31 00:00:00Z]
            }
            |> P2P.add_and_connect_node()

          node ->
            # If we already have the node in memory, we keep the values as it
            P2P.connect_nodes([node])
        end

        Logger.info("First enrolled node added into P2P MemTable")

        closest_nodes =
          (new_seeds ++ closest_nodes)
          |> P2P.distinct_nodes()
          |> Enum.reject(&(&1.first_public_key == Crypto.first_node_public_key()))

        P2P.connect_nodes(closest_nodes)

        Logger.info("Closest nodes and seeds loaded in the P2P view")

        {:ok, closest_nodes}

      {:error, _} ->
        get_closest_nodes_and_renew_seeds(rest, patch)
    end
  end

  def get_closest_nodes_and_renew_seeds([], _), do: {:error, :network_issue}

  @doc """
  Notify the beacon chain for the first node public key about the readiness of the node and the end of the bootstrapping
  """
  @spec publish_end_of_sync(slot_cron_interval :: binary()) :: :ok
  def publish_end_of_sync(slot_cron_interval \\ BeaconChain.get_slot_interval()) do
    ready_date = DateTime.utc_now()

    message = %NotifyEndOfNodeSync{
      node_public_key: Crypto.first_node_public_key(),
      timestamp: ready_date
    }

    <<_::8, _::8, subset::binary-size(1), _::binary>> = Crypto.first_node_public_key()

    Election.beacon_storage_nodes(
      subset,
      BeaconChain.next_slot(ready_date, slot_cron_interval),
      P2P.authorized_and_available_nodes(),
      Election.get_storage_constraints()
    )
    |> P2P.broadcast_message(message)
  end
end
