defmodule UnirisCore.Bootstrap do
  @moduledoc """
  Bootstrap a node in the Uniris network

  If the first node, the first node shared transaction is created and the transactions are self validated.

  Otherwise it will retrieve the necessary items to start the synchronization and send its new transaction to the closest node.
  """
  use Task

  require Logger

  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.Crypto
  alias UnirisCore.Storage
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.SharedSecrets
  alias UnirisCore.Beacon
  alias UnirisCore.BeaconSlot.NodeInfo
  alias UnirisCore.SelfRepair
  alias UnirisCore.Mining
  alias __MODULE__.IPLookup

  def start_link(opts) do
    ip = IPLookup.get_ip()

    port = Keyword.get(opts, :port)
    seeds_file = Keyword.get(opts, :seeds_file)

    Task.start_link(__MODULE__, :run, [
      ip,
      port,
      SelfRepair.last_sync_date(),
      Application.app_dir(:uniris_core, seeds_file)
    ])
  end

  def run(ip, port, last_sync_date, seeds_file) do
    Logger.info("Bootstraping starting")

    first_public_key = Crypto.node_public_key(0)
    patch = P2P.get_geo_patch(ip)

    network_seeds = bootstraping_seeds(seeds_file)

    with {:error, :transaction_not_exists} <-
           Storage.get_last_node_shared_secrets_transaction(),
         [%Node{first_public_key: key} | _] when key == first_public_key <- network_seeds do
      Logger.info("Network initialization...")
      init_network(ip, port)
    else
      _ ->
        load_nodes(network_seeds)
        diff_sync = DateTime.diff(DateTime.utc_now(), last_sync_date, :second)

        if Crypto.number_of_node_keys() == 0 do
          Logger.info("Node initialization...")
          first_initialization(ip, port, patch, network_seeds, seeds_file)
        else
          case P2P.node_info() do
            # TODO: change the diff sync parameter when the self repair will be moved to daily
            %Node{ip: prev_ip, port: prev_port} when ip != prev_ip or port != prev_port or diff_sync > 3 ->
              Logger.info("Update node chain...")
              update_node(ip, port, patch, network_seeds, seeds_file)
            _ ->
              :ok
          end
        end
    end

    Logger.info("Bootstraping finished!")
  end

  defp init_network(ip, port) do
    Logger.info("Create storage nonce")
    storage_nonce_seed = :crypto.strong_rand_bytes(32)
    {_, pv} = Crypto.generate_deterministic_keypair(storage_nonce_seed)
    Crypto.decrypt_and_set_storage_nonce(Crypto.ec_encrypt(pv, Crypto.node_public_key()))

    Logger.info("Create first node transaction")
    tx = create_node_transaction(ip, port)
    Mining.start(tx, "", [])
    Process.sleep(3000)

    Node.set_ready(Crypto.node_public_key(0), tx.timestamp)

    init_node_shared_secrets_chain()
    SelfRepair.start_sync(P2P.get_geo_patch(ip), false)
  end

  defp init_node_shared_secrets_chain() do
    aes_key = :crypto.strong_rand_bytes(32)

    encrypted_aes_key = Crypto.ec_encrypt(aes_key, Crypto.node_public_key())

    :crypto.strong_rand_bytes(32)
    |> Crypto.aes_encrypt(aes_key)
    |> Crypto.decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_aes_key)

    daily_nonce_seed = :crypto.strong_rand_bytes(32)
    authorized_public_keys = [Crypto.node_public_key(0)]

    tx =
      SharedSecrets.new_node_shared_secrets_transaction(
        authorized_public_keys,
        daily_nonce_seed,
        aes_key
      )

    Mining.start(tx, "", [])

    Node.authorize(Crypto.node_public_key(0), tx.timestamp)

    Crypto.decrypt_and_set_daily_nonce_seed(
      Crypto.aes_encrypt(daily_nonce_seed, aes_key),
      Crypto.ec_encrypt(aes_key, Crypto.node_public_key())
    )
  end

  defp first_initialization(ip, port, patch, network_seeds, seeds_file) do
    [closest_nodes, new_seeds] =
      network_seeds
      |> Enum.random()
      |> P2P.send_message([{:closest_nodes, patch}, :new_seeds])

    load_nodes(new_seeds ++ closest_nodes)
    update_seeds(seeds_file, new_seeds)

    Logger.info("Create first node transaction")
    tx = create_node_transaction(ip, port)
    send_message({:new_transaction, tx}, closest_nodes)

    case P2P.send_message(
           List.first(closest_nodes),
           {:get_storage_nonce, Crypto.node_public_key()}
         ) do
      {:ok, encrypted_nonce} ->
        Crypto.decrypt_and_set_storage_nonce(encrypted_nonce)
        Logger.info("Storage nonce set")

        nodes = P2P.send_message(List.first(closest_nodes), :list_nodes)
        load_nodes(nodes)
        Logger.info("Node list refreshed")

        Logger.info("Start synchronization")

        SelfRepair.start_sync(patch)

        receive do
          :sync_finished ->
            publish_readyness()
        end

      _ ->
        Logger.error("Transaction failed")
    end
  end

  defp update_node(ip, port, patch, network_seeds, seeds_file) do
    [closest_nodes, new_seeds] =
      network_seeds
      |> Enum.random()
      |> P2P.send_message([{:closest_nodes, patch}, :new_seeds])

    update_seeds(seeds_file, new_seeds)
    load_nodes(new_seeds ++ closest_nodes)
    Logger.info("Node list refreshed")

    tx = create_node_transaction(ip, port)
    send_message({:new_transaction, tx}, closest_nodes)

    Logger.info("Start synchronization")
    SelfRepair.start_sync(patch)

    receive do
      :sync_finished ->
        publish_readyness()
    end
  end

  defp publish_readyness() do
    subset = Beacon.subset_from_address(Crypto.node_public_key(0))

    ready_date = DateTime.utc_now()

    subset
    |> Beacon.get_pool(ready_date)
    |> Task.async_stream(fn node ->
      P2P.send_message(
        node,
        {:add_node_info, subset,
         %NodeInfo{public_key: Crypto.node_public_key(), ready?: true, timestamp: ready_date}}
      )
    end)
    |> Stream.run()
  end

  defp create_node_transaction(ip, port) do
    Transaction.new(:node, %TransactionData{
      content: """
      ip: #{stringify_ip(ip)}
      port: #{port}
      """
    })
  end

  defp load_nodes(nodes) do
    nodes
    |> Enum.uniq()
    |> Enum.each(
      fn node = %Node{
           first_public_key: first_public_key,
           last_public_key: last_public_key,
           ip: ip,
           port: port,
           enrollment_date: enrollment_date,
           authorized?: authorized?,
           authorization_date: authorization_date,
           ready?: ready?,
           ready_date: ready_date
         } ->
        case P2P.node_info(first_public_key) do
          {:error, :not_found} ->
            P2P.add_node(node)

          {:ok, _} ->
            Node.update_basics(first_public_key, last_public_key, ip, port)
            Node.set_enrollment_date(first_public_key, enrollment_date)

            if ready? do
              Node.set_ready(first_public_key, ready_date)
            end

            if authorized? do
              Node.authorize(first_public_key, authorization_date)
            end
        end
      end
    )
  end

  defp bootstraping_seeds(seeds_file) do
    case Application.get_env(:uniris_core, __MODULE__)[:seeds] do
      nil ->
        seeds_file
        |> File.read!()
        |> extract_seeds

      seeds ->
        extract_seeds(seeds)
    end
  end

  defp extract_seeds(seeds_str) do
    seeds_str
    |> String.split("\n", trim: true)
    |> Enum.map(fn seed ->
      [ip, port, public_key] = String.split(seed, ":")
      {:ok, ip} = ip |> String.to_charlist() |> :inet.parse_address()

      %Node{
        ip: ip,
        port: String.to_integer(port),
        last_public_key: public_key |> Base.decode16!(),
        first_public_key: public_key |> Base.decode16!()
      }
    end)
  end

  defp update_seeds(_, []), do: :ok

  defp update_seeds(seeds_file, seeds) when is_list(seeds) do
      seeds
      |> Enum.reject(& &1.first_public_key == Crypto.node_public_key(0))
      |> Enum.reduce([], fn %Node{ip: ip, port: port, first_public_key: public_key}, acc ->
        acc ++ ["#{stringify_ip(ip)}:#{port}:#{public_key |> Base.encode16()}"]
      end)
      |> Enum.join("\n")
      |> case do
        "" ->
          :ok
        seeds_str ->
          File.write!(seeds_file, seeds_str, [:write])
      end
  end

  defp stringify_ip(ip), do: :inet_parse.ntoa(ip)

  defp send_message(msg, [closest_node | rest]) do
    try do
      P2P.send_message(closest_node, msg)
    rescue
      e ->
        Logger.error(e)
        send_message(msg, rest)
    end
  end

  defp send_message(_, []), do: raise("Network issue")
end
