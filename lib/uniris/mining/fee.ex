defmodule Uniris.Mining.Fee do
  @moduledoc false

  alias Uniris.Transaction
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.NodeMovement

  @storage_node_rate 0.5
  @cross_validation_node_rate 0.4
  @coordinator_rate 0.095
  @welcome_rate 0.005

  @doc """
  Determines the fee for a given transaction

  Network transactions cost 0.0
  For others a dedicated algorithm is used depending on the complexity of the transaction
  """
  @spec compute(Transaction.pending()) :: float()
  def compute(tx = %Transaction{type: type}) do
    if Transaction.network_type?(type) do
      0.0
    else
      do_compute(tx)
    end
  end

  defp do_compute(_tx) do
    # TODO: implement the fee computation algorithm
    0.1
  end

  @doc """
  Distribute fees to reward nodes involved during the transaction mining
  (welcome node, coordinator, cross validator, previous storage nodes)
  """
  @spec distribute(
          fee :: float(),
          welcome_node :: Uniris.Crypto.key(),
          coordinator_public_key :: Uniris.Crypto.key(),
          validation_node_public_keys :: nonempty_list(Uniris.Crypto.key()),
          previous_storage_node_public_keys :: list(Uniris.Crypto.key())
        ) ::
          rewards :: list(Movement.t())
  def distribute(
        fee,
        welcome_node,
        coordinator,
        cross_validation_nodes,
        previous_storage_nodes
      )
      when is_list(cross_validation_nodes) and is_list(previous_storage_nodes) and
             length(cross_validation_nodes) > 0 do
    storage_node_rewards = fee * @storage_node_rate
    cross_validation_nodes_rewards = fee * @cross_validation_node_rate
    coordinator_node_rewards = fee * @coordinator_rate
    welcome_node_reward = fee * @welcome_rate

    # Split the cross validation node rewards among the cross validation nodes
    cross_validation_nodes_reward =
      cross_validation_nodes_rewards / length(cross_validation_nodes)

    case length(previous_storage_nodes) do
      0 ->
        # Add the reward for the previous storage nodes because the previous chain does not exists
        # and the validation nodes made the request with nothing returned
        # An additional reward equal of the storage node rewards is split among validation nodes
        additional_reward = storage_node_rewards / (length(cross_validation_nodes) + 1)

        [
          [
            %NodeMovement{to: welcome_node, amount: welcome_node_reward},
            %NodeMovement{to: coordinator, amount: coordinator_node_rewards + additional_reward}
          ],
          Enum.map(
            cross_validation_nodes,
            &%NodeMovement{to: &1, amount: cross_validation_nodes_reward + additional_reward}
          )
        ]
        |> :lists.flatten()

      nb_storage_nodes ->
        # Split the storage node rewards among the previous storage nodes
        storage_node_reward = storage_node_rewards / nb_storage_nodes

        [
          [
            %NodeMovement{to: welcome_node, amount: welcome_node_reward},
            %NodeMovement{to: coordinator, amount: coordinator_node_rewards}
          ],
          Enum.map(
            cross_validation_nodes,
            &%NodeMovement{to: &1, amount: cross_validation_nodes_reward}
          ),
          Enum.map(previous_storage_nodes, &%NodeMovement{to: &1, amount: storage_node_reward})
        ]
        |> :lists.flatten()
    end
  end
end
