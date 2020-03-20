defmodule UnirisP2PServer.MessageHandler do
  @moduledoc false

  require Logger

  alias UnirisChain, as: Chain
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisP2P, as: P2P
  alias UnirisElection, as: Election
  alias UnirisValidation, as: Validation
  alias UnirisCrypto, as: Crypto
  alias UnirisP2PServer.TaskSupervisor
  alias UnirisSync, as: Sync

  @doc """
  Process message coming from a P2P request by acting as a message controller/broker
  """
  @spec process(message :: tuple()) :: any()
  def process(:new_seeds) do
    P2P.list_nodes()
    |> Enum.filter(& &1.authorized?)
    |> Enum.take_random(5)
  end

  def process({:closest_nodes, network_patch}) do
    network_patch
    |> P2P.nearest_nodes(P2P.list_nodes())
    |> Enum.take(5)
  end

  def process({:bootstrap_crypto_seeds, pub}) do
    {:ok, %Transaction{data: %{keys: %{authorized_keys: authorized_keys, secret: secret}}}} =
      Chain.get_last_node_shared_secrets_transaction()

    aes_key = Crypto.ec_decrypt_with_node_key!(Map.get(authorized_keys, Crypto.node_public_key()))

    %{origin_keys_seeds: origin_keys_seeds, storage_nonce_seed: storage_nonce_seed} =
      Crypto.aes_decrypt!(secret, aes_key)

    %{
      origin_keys_seeds: Crypto.ec_encrypt(origin_keys_seeds, pub),
      storage_nonce_seed: Crypto.ec_encrypt(storage_nonce_seed, pub)
    }
  end

  def process({:new_transaction, tx = %Transaction{}}) do
    welcome_node = Crypto.node_public_key()
    validation_nodes = Election.validation_nodes(tx) |> Enum.map(& &1.last_public_key)

    Enum.each(validation_nodes, fn node ->
      Task.Supervisor.start_child(TaskSupervisor, fn ->
        P2P.send_message(node, {:start_mining, tx, welcome_node, validation_nodes})
      end)
    end)
  end

  def process({:get_transaction, tx_address}) do
    Chain.get_transaction(tx_address)
  end

  def process({:get_transaction_chain, tx_address}) do
    Chain.get_transaction_chain(tx_address)
  end

  def process({:get_unspent_outputs, tx_address}) do
    Chain.get_unspent_output_transactions(tx_address)
  end

  def process({:get_proof_of_integrity, tx_address}) do
    with {:ok, %Transaction{validation_stamp: %ValidationStamp{proof_of_integrity: poi}}} <-
           Chain.get_transaction(tx_address) do
      {:ok, poi}
    end
  end

  def process({:start_mining, tx = %Transaction{}, welcome_node_public_key, validation_nodes}) do
    Validation.start_mining(tx, welcome_node_public_key, validation_nodes)
  end

  def process(
        {:add_context, tx_address, validation_node, previous_storage_nodes, validation_nodes_view,
         chain_storage_nodes_view, beacon_storage_nodes_view}
      ) do
    Validation.add_context(
      tx_address,
      validation_node,
      previous_storage_nodes,
      validation_nodes_view,
      chain_storage_nodes_view,
      beacon_storage_nodes_view
    )
  end

  def process({:set_replication_trees, tx_address, trees}) do
    Validation.set_replication_trees(tx_address, trees)
  end

  def process(
        {:replicate_chain,
         tx = %Transaction{validation_stamp: %ValidationStamp{}, cross_validation_stamps: stamps}}
      )
      when is_list(stamps) and length(stamps) >= 0 do
    Validation.replicate_chain(tx)
  end

  def process(
        {:replicate_transaction,
         tx = %Transaction{validation_stamp: %ValidationStamp{}, cross_validation_stamps: stamps}}
      )
      when is_list(stamps) and length(stamps) >= 0 do
    Validation.replicate_transaction(tx)
  end

  def process({:replicate_address, address, timestamp})
      when is_binary(address) and is_integer(timestamp) do
    Validation.replicate_address(address, timestamp)
  end

  def process({:acknowledge_storage, tx_address}) do
    Logger.debug("Transaction #{Base.encode16(tx_address)} storage acknowledge")
    :ok
  end

  def process({:cross_validate, tx_address, stamp = %ValidationStamp{}})
      when is_binary(tx_address) do
    Validation.cross_validate(tx_address, stamp)
  end

  def process({:cross_validation_done, tx_address, {signature, inconsistencies, public_key}})
      when is_binary(tx_address) and is_binary(signature) and is_list(inconsistencies) and
             is_binary(public_key) do
    Validation.add_cross_validation_stamp(tx_address, {signature, inconsistencies, public_key})
  end

  def process({:beacon_addresses, subset, last_sync_date}) when is_binary(subset) and is_integer(last_sync_date) do
    Sync.get_beacon_addresses(subset, last_sync_date)
  end

end
