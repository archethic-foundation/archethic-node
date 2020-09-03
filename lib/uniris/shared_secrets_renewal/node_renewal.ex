defmodule Uniris.SharedSecretsRenewal.NodeRenewal do
  @moduledoc false

  alias Uniris.Crypto

  alias Uniris.Election
  alias Uniris.Election.ValidationConstraints

  alias Uniris.P2P
  alias Uniris.P2P.Message.StartMining
  alias Uniris.P2P.Node

  alias Uniris.SharedSecretsRenewal.TransactionBuilder

  alias Uniris.Storage.Memory.NetworkLedger

  alias Uniris.TaskSupervisor

  require Logger

  @doc """
  Determine if the node is a valid candidate to be the initiator of the node shared secrets renewal
  """
  @spec initiator?() :: boolean()
  def initiator? do
    authorized_nodes = Enum.filter(NetworkLedger.list_authorized_nodes(), & &1.available?)

    # Forecast the new shared key transaction address
    key_index = Crypto.number_of_node_shared_secrets_keys()
    next_public_key = Crypto.node_shared_secrets_public_key(key_index + 1)
    next_address = Crypto.hash(next_public_key)

    # Determine if the current node is in charge to the send the new transaction
    [%Node{last_public_key: key} | _] = Election.storage_nodes(next_address, authorized_nodes)

    key == Crypto.node_public_key()
  end

  @doc """
  Build and send the transaction with the new authorized nodes and daily nonce
  """
  @spec send_transaction() :: :ok
  def send_transaction do
    new_authorized_nodes()
    |> Enum.map(& &1.last_public_key)
    |> build_transaction()
    |> send_transaction()
  end

  # Build the node shareds secrets transaction
  defp build_transaction(authorized_nodes) do
    TransactionBuilder.new_node_shared_secrets_transaction(
      :crypto.strong_rand_bytes(32),
      :crypto.strong_rand_bytes(32),
      authorized_nodes
    )
  end

  # Dispatch the transaction to the validation nodes
  defp send_transaction(tx) do
    validation_nodes = Election.validation_nodes(tx)
    validation_nodes_public_keys = Enum.map(validation_nodes, & &1.last_public_key)

    TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(validation_nodes, fn node ->
      P2P.send_message(node, %StartMining{
        transaction: tx,
        welcome_node_public_key: Crypto.node_public_key(),
        validation_node_public_keys: validation_nodes_public_keys
      })
    end)
    |> Stream.run()
  end

  #  Find out the next authorized nodes based on the previous ones and the heuristic validation constraints
  #  to embark new validation nodes in the network
  defp new_authorized_nodes do
    %ValidationConstraints{
      min_validation_number: min_validation_number,
      min_geo_patch: min_geo_patch
    } = Election.validation_constraints()

    previous_authorized_nodes = NetworkLedger.list_authorized_nodes()

    # TODO: Exclude nodes from malicious behavior detection
    select_new_authorized_nodes(
      NetworkLedger.list_ready_nodes() -- previous_authorized_nodes,
      min_validation_number,
      min_geo_patch.(),
      previous_authorized_nodes
    )
  end

  # Using the minimum number of validation and minimum geographical distribution
  # A selection is perfomed to add new validation nodes based on those constraints
  defp select_new_authorized_nodes([node | rest], min_validation_number, min_geo_patch, acc) do
    distinct_geo_patches =
      acc
      |> Enum.map(& &1.geo_patch)
      |> Enum.uniq()

    if length(acc) < min_validation_number and length(distinct_geo_patches) < min_geo_patch do
      select_new_authorized_nodes(rest, min_validation_number, min_geo_patch, [node | acc])
    else
      acc
    end
  end

  defp select_new_authorized_nodes([], _, _, acc), do: acc

  @doc """
  Apply the node renewal and shared secret
  """
  @spec apply(
          authorized_node_public_keys :: list(Crypto.key()),
          authorization_date :: DateTime.t(),
          encrypted_key :: binary(),
          secret :: binary()
        ) :: :ok
  def apply(authorized_nodes, authorization_date, encrypted_key, secret) do
    load_authorized_nodes(authorized_nodes, authorization_date)
    load_daily_nonce_seed(encrypted_key, secret)
  end

  defp load_authorized_nodes(authorized_nodes, authorization_date) do
    :ok = NetworkLedger.reset_authorized_nodes()

    Enum.each(authorized_nodes, fn node_public_key ->
      :ok = NetworkLedger.authorize_node(node_public_key, authorization_date)
      Logger.info("New authorized node #{Base.encode16(node_public_key)}")
    end)
  end

  defp load_daily_nonce_seed(encrypted_key, secret) do
    # 60 == byte size of the aes encryption of 32 byte of seed
    encrypted_daily_nonce_seed = :binary.part(secret, 0, 60)
    encrypted_transaction_seed = :binary.part(secret, 60, 60)

    :ok =
      Crypto.decrypt_and_set_node_shared_secrets_transaction_seed(
        encrypted_transaction_seed,
        encrypted_key
      )

    :ok = Crypto.decrypt_and_set_daily_nonce_seed(encrypted_daily_nonce_seed, encrypted_key)

    Logger.info("Node shared secrets seed loaded")
  end
end
