defmodule UnirisValidation.DefaultImpl.Reward do
  @moduledoc false

  @storage_node_rate 0.5
  @validation_node_rate 0.4
  @coordinator_rate 0.095
  @welcome_rate 0.005
  # @network_pool_rate 0.1

  @doc ~S"""
   Compute node rewards based on the given fee.

  The following distribution is applicated:
    - Storage nodes: 50%
    - Validation nodes: 40%
    - Coordinator: 9.5%
    - Welcome node: 0.5%

  ## Examples

    iex> UnirisValidation.DefaultImpl.Reward.distribute_fee(
    ...> 0.5,
    ...> "503EF04022CDAA3F0F402A1C2524ED3782E09F228BC16DEB1766051C86880F8D",
    ...> "F35EB8260981AC5D8268B7B323277C8FB44D73B81DCC603B0E9CEB4B406A18AD",
    ...> ["5D0AE5A5B686030AD630119F3494B4852E3990BF196C117D574FD32BEB747FC7", "074CA174E4763A169F714C0D37187C5AC889683B4BBE9B0859C4073A690B7DF1"],
    ...> ["5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23", "AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE", "4d75266a648f6d67576e6c77138c07042077b815fb5255d7f585cd36860da19e"])
    [
      {"503EF04022CDAA3F0F402A1C2524ED3782E09F228BC16DEB1766051C86880F8D", 0.0025},
      {"F35EB8260981AC5D8268B7B323277C8FB44D73B81DCC603B0E9CEB4B406A18AD", 0.0475},
      {"5D0AE5A5B686030AD630119F3494B4852E3990BF196C117D574FD32BEB747FC7", 0.1},
      {"074CA174E4763A169F714C0D37187C5AC889683B4BBE9B0859C4073A690B7DF1", 0.1},
      {"5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23", 0.08333333333333333},
      {"AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE", 0.08333333333333333},
      {"4d75266a648f6d67576e6c77138c07042077b815fb5255d7f585cd36860da19e", 0.08333333333333333}
    ]
  """
  @spec distribute_fee(float(), binary(), binary(), nonempty_list(binary()), nonempty_list(binary())) ::
          nonempty_list({binary(), number()})
  def distribute_fee(
        fee,
        welcome_node,
        coordinator,
        validation_nodes,
        previous_storage_nodes
      )
      when is_list(validation_nodes) and is_list(previous_storage_nodes) and
             length(validation_nodes) > 0 and length(previous_storage_nodes) > 0 do
    storage_node_rewards = fee * @storage_node_rate
    validation_node_rewards = fee * @validation_node_rate
    coordinator_node_rewards = fee * @coordinator_rate
    welcome_node_reward = fee * @welcome_rate
    # network_pool_rewards = fee * @network_pool_rate

    validation_nodes = Enum.filter(validation_nodes, &(&1 != coordinator))
    # Split the storage node rewards among the previous storage nodes
    storage_node_reward = storage_node_rewards / length(previous_storage_nodes)

    # Split the validation node rewards among the cross validation nodes
    validation_node_reward = validation_node_rewards / length(validation_nodes)

    [{welcome_node, welcome_node_reward}, {coordinator, coordinator_node_rewards}]
    ++ Enum.map(validation_nodes, fn n -> {n, validation_node_reward} end)
    ++ Enum.map(previous_storage_nodes, fn n -> {n, storage_node_reward} end)
  end

end
