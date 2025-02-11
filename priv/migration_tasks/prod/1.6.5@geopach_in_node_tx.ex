defmodule Migration_1_6_5 do
  @moduledoc """
  Migration script to add geopatch to a node's transaction.
  """

  alias Archethic.Crypto
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.NodeConfig
  alias Archethic.PubSub
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.Utils

  require Logger

  def run() do
    P2P.list_nodes()
    |> Enum.sort_by(& &1.first_public_key)
    |> process_next_node(Crypto.first_node_public_key())
  end

  defp process_next_node([], current_node_pk) do
    Logger.warning("Reached end of node list, node may not have been updated",
      node: Base.encode16(current_node_pk)
    )
  end

  defp process_next_node([node = %Node{first_public_key: node_pk} | _], current_node_pk)
       when node_pk == current_node_pk do
    Logger.info("Send transaction to update geo patch")
    send_node_transaction(node)
  end

  defp process_next_node([node = %Node{first_public_key: node_key} | rest], current_node_pk) do
    Logger.info("Processing node", node: Base.encode16(node_key))

    if geopatch_in_last_transaction?(node) do
      Logger.info("Geo patch already updated", node: Base.encode16(node_key))
    else
      Logger.info("Waiting for node to update", node: Base.encode16(node_key))

      PubSub.register_to_new_transaction_by_type(:node)
      wait_node_update(node)
      PubSub.unregister_to_new_transaction_by_type(:node)
    end

    process_next_node(rest, current_node_pk)
  end

  defp wait_node_update(node = %Node{first_public_key: node_key}) do
    receive do
      {:new_transaction, address, :node, _timestamp} ->
        {:ok,
         %Transaction{previous_public_key: previous_pk, data: %TransactionData{content: content}}} =
          TransactionChain.get_transaction(address)

        first_pk = TransactionChain.get_first_public_key(previous_pk)

        if first_pk == node_key and geopatch_in_tx_content?(content),
          do: Logger.info("Node updated", node: Base.encode16(node_key)),
          else: wait_node_update(node)
    after
      60_000 ->
        Logger.warning("Timeout waiting for updates from node", node: Base.encode16(node_key))
    end
  end

  defp geopatch_in_last_transaction?(%Node{last_address: last_address}) do
    case TransactionChain.get_transaction(last_address) do
      {:ok, %Transaction{data: %TransactionData{content: content}}} ->
        geopatch_in_tx_content?(content)

      {:error, _} ->
        false
    end
  end

  defp geopatch_in_tx_content?(content) do
    {:ok, %NodeConfig{geo_patch: geo_patch}} = Node.decode_transaction_content(content)
    geo_patch != nil
  end

  defp send_node_transaction(node = %Node{last_address: last_address}) do
    geo_patch_update_date = Application.get_env(:archethic, :geopatch_update_time)

    node_config = %NodeConfig{origin_public_key: origin_public_key} = NodeConfig.from_node(node)

    node_config = %NodeConfig{
      node_config
      | geo_patch_update: DateTime.utc_now() |> DateTime.add(geo_patch_update_date, :millisecond),
        origin_certificate: Crypto.get_key_certificate(origin_public_key)
    }

    {:ok, %Transaction{data: %TransactionData{code: code}}} =
      TransactionChain.get_transaction(last_address, data: [:code])

    tx =
      Transaction.new(:node, %TransactionData{
        code: code,
        content: Node.encode_transaction_content(node_config)
      })

    Archethic.send_new_transaction(tx, forward?: true)

    nodes =
      P2P.authorized_and_available_nodes()
      |> Enum.filter(&P2P.node_connected?/1)
      |> P2P.sort_by_nearest_nodes()

    case Utils.await_confirmation(tx.address, nodes) do
      {:ok, _} -> Logger.info("Node update successful")
      {:error, reason} -> Logger.error("Cannot update node: #{inspect(reason)}")
    end
  end
end
