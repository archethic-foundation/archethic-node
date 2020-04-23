defmodule UnirisCore.Mining.Fee do
  @moduledoc false

  alias UnirisCore.Transaction

  @storage_node_rate 0.5
  @validation_node_rate 0.4
  @coordinator_rate 0.095
  @welcome_rate 0.005

  # TODO: use the network pool in the rewards and the fee rate

  @spec compute(Transaction.pending()) :: float()
  def compute(_tx = %Transaction{type: :node}), do: 0.0
  def compute(_tx = %Transaction{type: :node_shared_secrets}), do: 0.0

  def compute(_tx = %Transaction{}) do
    0.1
  end

  @spec distribute(
          fee :: float(),
          welcome_node :: UnirisCore.Crypto.key(),
          coordinator_public_key :: UnirisCore.Crypto.key(),
          validation_node_public_keys :: nonempty_list(UnirisCore.Crypto.key()),
          previous_storage_node_public_keys :: list(UnirisCore.Crypto.key())
        ) ::
          rewards :: nonempty_list({node_public_key :: binary(), amount :: float()})
  def distribute(
        fee,
        welcome_node,
        coordinator,
        validation_nodes,
        previous_storage_nodes
      )
      when is_list(validation_nodes) and is_list(previous_storage_nodes) and
             length(validation_nodes) > 0 do
    storage_node_rewards = fee * @storage_node_rate
    validation_node_rewards = fee * @validation_node_rate
    coordinator_node_rewards = fee * @coordinator_rate
    welcome_node_reward = fee * @welcome_rate

    # Split the validation node rewards among the cross validation nodes
    validation_node_reward = validation_node_rewards / length(validation_nodes)

    case length(previous_storage_nodes) do
      0 ->
        [{welcome_node, welcome_node_reward}, {coordinator, coordinator_node_rewards}] ++
          Enum.map(validation_nodes, fn n -> {n, validation_node_reward} end)

      nb_storage_nodes ->
        # Split the storage node rewards among the previous storage nodes
        storage_node_reward = storage_node_rewards / nb_storage_nodes

        [{welcome_node, welcome_node_reward}, {coordinator, coordinator_node_rewards}] ++
          Enum.map(validation_nodes, fn n -> {n, validation_node_reward} end) ++
          Enum.map(previous_storage_nodes, fn n -> {n, storage_node_reward} end)
    end
  end
end
