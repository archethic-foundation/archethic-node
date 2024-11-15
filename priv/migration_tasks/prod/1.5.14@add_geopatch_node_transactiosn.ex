defmodule Migration_1_5_14 do
  @moduledoc """
  Migration script to add geopatch to a node's transaction.
  """

  alias Archethic.Crypto
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.Utils
  alias Archethic.PubSub

  require Logger

  def run() do
    nodes = P2P.list_nodes() |> Enum.sort_by(& &1.first_public_key)

    execute_migration(nodes)
  end

  defp execute_migration([]) do
    :ok
  end

  defp execute_migration(nodes) do
    current_node_pk = Crypto.first_node_public_key()
    transaction_cache = %{}

    Enum.reduce_while(nodes, transaction_cache, fn node, transaction_cache ->
      node_pk = node.first_public_key
      Logger.info("Processing node", node: Base.encode16(node_pk))

      if geopatch_in_last_transaction?(node_pk) do
        Logger.info("Migration not needed for node", node: Base.encode16(node_pk))
        {:cont, Map.delete(transaction_cache, node_pk)}
      else
        if node_pk == current_node_pk do
          Logger.info("Starting migration for node", node: Base.encode16(node_pk))

          case send_node_transaction() do
            :ok ->
              Logger.info("Migration complete for node", node: Base.encode16(node_pk))
              {:halt, :ok}

            {:error, reason} ->
              Logger.error(
                "Migration failed (reason: #{inspect(reason)}) for",
                node: Base.encode16(node_pk)
              )

              {:halt, {:error, reason}}
          end
        else
          case Map.fetch(transaction_cache, node_pk) do
            {:ok, transaction} ->
              {:cont, process_transaction(transaction, Map.delete(transaction_cache, node_pk))}

            :error ->
              PubSub.register_to_new_transaction_by_type(:node)

              receive do
                {:new_transaction, address, :node, _timestamp} ->
                  with {:ok, %Transaction{previous_public_key: previous_pk} = transaction} <-
                         TransactionChain.get_transaction(address) do
                    first_pk = TransactionChain.get_first_public_key(previous_pk)

                    if first_pk == node_pk do
                      {:cont, process_transaction(transaction, transaction_cache)}
                    else
                      updated_cache = Map.put(transaction_cache, first_pk, transaction)
                      {:cont, updated_cache}
                    end
                  else
                    {:error, reason} ->
                      Logger.error(
                        "Failed to fetch transaction: #{inspect(reason)} for address",
                        address: Base.encode16(address)
                      )

                      {:cont, transaction_cache}
                  end
              after
                60_000 ->
                  Logger.error("Timeout waiting for updates from node",
                    node: Base.encode16(node_pk)
                  )

                  PubSub.unregister_to_new_transaction_by_type(:node)
                  {:cont, transaction_cache}
              end
          end
        end
      end
    end)
  end

  defp process_transaction(
         %Transaction{data: %TransactionData{content: content}},
         transaction_cache
       ) do
    case geopatch_in_transaction_content?(content) do
      true ->
        PubSub.unregister_to_new_transaction_by_type(:node)
        transaction_cache

      false ->
        transaction_cache
    end
  end

  defp geopatch_in_last_transaction?(node_pk) do
    case P2P.get_node_info(node_pk) do
      {:ok, %Node{last_address: last_address}} ->
        case TransactionChain.get_transaction(last_address) do
          {:ok, %Transaction{data: %TransactionData{content: content}}} ->
            geopatch_in_transaction_content?(content)

          {:error, _} ->
            false
        end

      {:error, _} ->
        false
    end
  end

  defp geopatch_in_transaction_content?(content) do
    with {:ok, _ip, _p2p_port, _http_port, _transport, _last_reward_address, _origin_public_key,
          _key_certificate, _mining_public_key,
          geo_patch} <- Node.decode_transaction_content(content) do
      geo_patch != nil
    else
      error ->
        false
    end
  end

  defp send_node_transaction() do
    %Node{
      ip: ip,
      port: port,
      http_port: http_port,
      transport: transport,
      reward_address: reward_address,
      origin_public_key: origin_public_key,
      last_address: last_address
    } = P2P.get_node_info()

    geopatch = Archethic.P2P.GeoPatch.from_ip(ip)

    mining_public_key = Crypto.mining_node_public_key()
    key_certificate = Crypto.get_key_certificate(origin_public_key)

    {:ok, %Transaction{data: %TransactionData{code: code}}} =
      TransactionChain.get_transaction(last_address, data: [:code])

    tx =
      Transaction.new(:node, %TransactionData{
        code: code,
        content:
          Node.encode_transaction_content(%{
            ip: ip,
            port: port,
            http_port: http_port,
            transport: transport,
            reward_address: reward_address,
            origin_public_key: origin_public_key,
            key_certificate: key_certificate,
            mining_public_key: mining_public_key,
            geo_patch: geopatch
          })
      })

    :ok = Archethic.send_new_transaction(tx, forward?: true)

    nodes =
      P2P.authorized_and_available_nodes()
      |> Enum.filter(&P2P.node_connected?/1)
      |> P2P.sort_by_nearest_nodes()

    case Utils.await_confirmation(tx.address, nodes) do
      {:ok, _} ->
        Logger.error("Mining node transaction successful.")
        :ok

      {:error, reason} ->
        Logger.error("Cannot update node transaction: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
