defmodule Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations do
  @moduledoc """
  Represents the ledger operations defined during the transaction mining regarding the network movements:
  - transaction movements
  - node rewards
  - unspent outputs
  - transaction fee
  """

  @storage_node_rate 0.5
  @cross_validation_node_rate 0.4
  @coordinator_rate 0.095
  @welcome_rate 0.005

  defstruct transaction_movements: [],
            node_movements: [],
            unspent_outputs: [],
            fee: 0.0

  alias Uniris.Crypto

  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  @typedoc """
  - Transaction movements: represents the pending transaction ledger movements
  - Node movements: represents the node rewards
  - Unspent outputs: represents the new unspent outputs
  - fee: represents the transaction fee distributed across the node movements
  """
  @type t() :: %__MODULE__{
          transaction_movements: list(TransactionMovement.t()),
          node_movements: list(NodeMovement.t()),
          unspent_outputs: list(UnspentOutput.t()),
          fee: float()
        }

  @doc """
  Create a new ledger operations from a pending transaction
  """
  @spec from_transaction(Transaction.t()) :: t()
  def from_transaction(tx = %Transaction{validation_stamp: nil, cross_validation_stamps: nil}) do
    movements =
      tx
      |> Transaction.get_movements()
      |> Enum.map(&%TransactionMovement{to: &1.to, amount: &1.amount})

    %__MODULE__{
      fee: Transaction.fee(tx),
      transaction_movements: movements
    }
  end

  @doc """
  Create node rewards and movements based on the transaction fee by distributing it using the different rates
  for each individual actor: welcome node, coordinator node, cross validation node, previous storage node

  ## Examples

      iex> %LedgerOperations{ fee: 0.5}
      ...> |> LedgerOperations.distribute_rewards(
      ...>    %Node{last_public_key: "503EF04022CDAA3F0F402A1C2524ED3782E09F228BC16DEB1766051C86880F8D"},
      ...>    %Node{last_public_key: "F35EB8260981AC5D8268B7B323277C8FB44D73B81DCC603B0E9CEB4B406A18AD"},
      ...>    [
      ...>       %Node{last_public_key: "5D0AE5A5B686030AD630119F3494B4852E3990BF196C117D574FD32BEB747FC7"},
      ...>       %Node{last_public_key: "074CA174E4763A169F714C0D37187C5AC889683B4BBE9B0859C4073A690B7DF1"}
      ...>    ],
      ...>    [
      ...>      %Node{last_public_key: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23"},
      ...>      %Node{last_public_key: "AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE"},
      ...>      %Node{last_public_key: "4D75266A648F6D67576E6C77138C07042077B815FB5255D7F585CD36860DA19E"}
      ...>    ]
      ...>  )
      %LedgerOperations{
         fee: 0.5,
         node_movements: [
            %NodeMovement{to: "074CA174E4763A169F714C0D37187C5AC889683B4BBE9B0859C4073A690B7DF1", amount: 0.1, roles: [:cross_validation_node] },
            %NodeMovement{to: "4D75266A648F6D67576E6C77138C07042077B815FB5255D7F585CD36860DA19E", amount: 0.08333333333333333, roles: [:previous_storage_node]},
            %NodeMovement{to: "503EF04022CDAA3F0F402A1C2524ED3782E09F228BC16DEB1766051C86880F8D", amount: 0.0025, roles: [:welcome_node]},
            %NodeMovement{to: "5D0AE5A5B686030AD630119F3494B4852E3990BF196C117D574FD32BEB747FC7", amount: 0.1, roles: [:cross_validation_node]},
            %NodeMovement{to: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23", amount: 0.08333333333333333, roles: [:previous_storage_node]},
            %NodeMovement{to: "AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE", amount: 0.08333333333333333, roles: [:previous_storage_node]},
            %NodeMovement{to: "F35EB8260981AC5D8268B7B323277C8FB44D73B81DCC603B0E9CEB4B406A18AD", amount: 0.0475, roles: [:coordinator_node]},
         ]
      }

    When some nodes has several roles (present in the network bootstrapping phase),
    a mapping per node and per role is perform to ensure the right amount of rewards.

      iex> %LedgerOperations{ fee: 0.5}
      ...> |> LedgerOperations.distribute_rewards(
      ...>    %Node{last_public_key: "503EF04022CDAA3F0F402A1C2524ED3782E09F228BC16DEB1766051C86880F8D"},
      ...>    %Node{last_public_key: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23"},
      ...>    [
      ...>       %Node{last_public_key: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23"},
      ...>       %Node{last_public_key: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23"}
      ...>    ],
      ...>    [
      ...>      %Node{last_public_key: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23"},
      ...>      %Node{last_public_key: "AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE"},
      ...>      %Node{last_public_key: "4D75266A648F6D67576E6C77138C07042077B815FB5255D7F585CD36860DA19E"}
      ...>    ]
      ...>  )
      %LedgerOperations{
         fee: 0.5,
         node_movements: [
            %NodeMovement{to: "4D75266A648F6D67576E6C77138C07042077B815FB5255D7F585CD36860DA19E", amount: 0.08333333333333333, roles: [:previous_storage_node]},
            %NodeMovement{to: "503EF04022CDAA3F0F402A1C2524ED3782E09F228BC16DEB1766051C86880F8D", amount: 0.0025, roles: [:welcome_node]},
            %NodeMovement{to: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23", amount: 0.23083333333333333, roles: [:coordinator_node, :cross_validation_node, :previous_storage_node] },
            %NodeMovement{to: "AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE", amount: 0.08333333333333333, roles: [:previous_storage_node] }
         ]
      }
  """
  @spec distribute_rewards(t(), Node.t(), Node.t(), list(Node.t()), list(Node.t())) ::
          t()
  def distribute_rewards(
        ops = %__MODULE__{fee: fee},
        %Node{last_public_key: welcome_node_public_key},
        %Node{last_public_key: coordinator_node_public_key},
        cross_validation_nodes,
        previous_storage_nodes
      )
      when is_list(cross_validation_nodes) and is_list(previous_storage_nodes) do
    cross_validation_node_reward =
      get_cross_validation_node_reward(fee, length(cross_validation_nodes))

    previous_storage_node_reward =
      get_previous_storage_reward(fee, length(previous_storage_nodes))

    role_distribution =
      [
        {:welcome_node, welcome_node_public_key},
        {:coordinator_node, coordinator_node_public_key}
      ] ++
        Enum.map(cross_validation_nodes, &{:cross_validation_node, &1.last_public_key}) ++
        Enum.map(previous_storage_nodes, &{:previous_storage_node, &1.last_public_key})

    node_movements =
      role_distribution
      |> group_roles_by_node
      |> Enum.to_list()
      |> sum_rewards(
        reward_per_role(fee, cross_validation_node_reward, previous_storage_node_reward)
      )
      |> Enum.map(fn {public_key, {roles, reward}} ->
        %NodeMovement{to: public_key, amount: reward, roles: roles}
      end)

    %{ops | node_movements: node_movements}
  end

  defp sum_rewards(_, _, acc \\ %{})

  defp sum_rewards([{public_key, roles} | tail], rewards_by_role, acc) do
    sum_node_rewards = Enum.reduce(roles, 0.0, &(&2 + Map.get(rewards_by_role, &1)))
    sum_rewards(tail, rewards_by_role, Map.put(acc, public_key, {roles, sum_node_rewards}))
  end

  defp sum_rewards([], _, acc), do: acc

  defp group_roles_by_node(_, acc \\ %{})

  defp group_roles_by_node([{role, public_key} | tail], acc) do
    group_roles_by_node(tail, Map.update(acc, public_key, [role], &Enum.uniq([role | &1])))
  end

  defp group_roles_by_node(_, acc) do
    Enum.map(acc, fn {public_key, roles} ->
      {public_key, Enum.reverse(roles)}
    end)
  end

  @doc """
  Return the reward for the welcome node based on the fee and its rate

  The allocation for welcome node represents 0.5%

  ## Examples

      iex> LedgerOperations.get_welcome_node_reward(1)
      0.005
  """
  @spec get_welcome_node_reward(fee :: float()) :: float()
  def get_welcome_node_reward(fee), do: fee * @welcome_rate

  @doc """
  Return the reward for the coordinator node based on the fee and its rate

  The allocation for coordinator represents 9.5%

  ## Examples

      iex> LedgerOperations.get_coordinator_node_reward(1)
      0.095
  """
  @spec get_coordinator_node_reward(fee :: float()) :: float()
  def get_coordinator_node_reward(fee), do: fee * @coordinator_rate

  @doc """
  Return the reward for each cross validation node based on the fee, the rate and the number of cross validation nodes

  The allocation for the entire cross validation nodes represents 40% of the fee 

  ## Examples

      iex> LedgerOperations.get_cross_validation_node_reward(1, 2)
      0.2
  """
  @spec get_cross_validation_node_reward(
          fee :: float(),
          nb_cross_validation_nodes :: non_neg_integer()
        ) :: float()
  def get_cross_validation_node_reward(fee, nb_cross_validation_nodes) do
    fee * @cross_validation_node_rate / nb_cross_validation_nodes
  end

  @doc """
  Return the reward for each previous storage node based on the fee, its rate and the number of storage nodes

  The allocation for the entire previous storages nodes represents 50% of the fee 

  ## Examples

      iex> LedgerOperations.get_previous_storage_reward(1, 5)
      0.1

      iex> LedgerOperations.get_previous_storage_reward(1, 0)
      0.0
  """
  @spec get_previous_storage_reward(
          fee :: float(),
          nb_previous_storage_nodes :: non_neg_integer()
        ) :: float()
  def get_previous_storage_reward(_fee, 0), do: 0.0

  def get_previous_storage_reward(fee, nb_previous_storage_nodes) do
    fee * @storage_node_rate / nb_previous_storage_nodes
  end

  @doc """
  Returns the amount to spend from the transaction movements and the fee

  ## Examples

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 10.4},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 2.17}
      ...>    ],
      ...>    fee: 0.40
      ...> }
      ...> |> LedgerOperations.total_to_spend()
      12.97
  """
  @spec total_to_spend(t()) :: float()
  def total_to_spend(%__MODULE__{transaction_movements: transaction_movements, fee: fee}) do
    uco_to_spend = Enum.reduce(transaction_movements, 0.0, &(&2 + &1.amount))
    uco_to_spend + fee
  end

  @doc """
  Determine if the funds are sufficient with the given amount of unspent outputs for total of uco to spend

  ## Examples

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 10.4},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 2.17}
      ...>    ],
      ...>    fee: 0.40
      ...> }
      ...> |> LedgerOperations.enough_funds?(20.0)
      true
  """
  @spec enough_funds?(t(), float()) :: boolean()
  def enough_funds?(ops = %__MODULE__{}, amount) when is_float(amount) do
    total_to_spend(ops) <= amount
  end

  @doc """
  Determine if the funds are sufficient with the given unspent outputs for total of uco to spend

  ## Examples

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 10.4},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 2.17}
      ...>    ],
      ...>    fee: 0.40
      ...> }
      ...> |> LedgerOperations.sufficient_funds?([])
      false

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 10.4},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 2.17}
      ...>    ],
      ...>    fee: 0.40
      ...> }
      ...> |> LedgerOperations.sufficient_funds?([%UnspentOutput{from: "@Charlie5", amount: 30}])
      true
  """
  @spec sufficient_funds?(t(), list(UnspentOutput.t() | TransactionInput.t())) :: boolean()
  def sufficient_funds?(operations = %__MODULE__{}, inputs) when is_list(inputs) do
    amount_received = Enum.reduce(inputs, 0.0, &(&2 + &1.amount))
    amount_received >= total_to_spend(operations)
  end

  @doc """
  Use the necessary inputs to satisfy the uco amount to spend

  The remaining unspent outputs will go to the change address

  ## Examples

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 10.4},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 2.17}
      ...>    ],
      ...>    fee: 0.40
      ...> }
      ...> |> LedgerOperations.consume_inputs("@Alice2", [%UnspentOutput{from: "@Bob3", amount: 20}])
      %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Bob4", amount: 10.4},
            %TransactionMovement{to: "@Charlie2", amount: 2.17}
          ],
          fee: 0.40,
          node_movements: [],
          unspent_outputs: [
            %UnspentOutput{from: "@Alice2", amount: 7.029999999999999}
          ]
      }
  """
  @spec consume_inputs(
          ledger_operations :: t(),
          change_address :: binary(),
          inputs :: UnspentOutput.t() | TransactionInput.t()
        ) ::
          t()
  def consume_inputs(ops = %__MODULE__{}, change_address, inputs) do
    uco_amount = Enum.reduce(inputs, 0.0, &(&2 + &1.amount))

    if uco_amount >= total_to_spend(ops) do
      sorted_inputs = Enum.sort_by(inputs, & &1.amount)

      new_unspent_outputs =
        do_consume_inputs(
          change_address,
          Enum.map(sorted_inputs, &%UnspentOutput{from: &1.from, amount: &1.amount}),
          total_to_spend(ops),
          0.0
        )

      %{ops | unspent_outputs: new_unspent_outputs}
    else
      %{ops | unspent_outputs: []}
    end
  end

  defp do_consume_inputs(change_address, unspent_outputs, remaining, change)
       when remaining == 0.0 and change > 0.0 do
    [%UnspentOutput{amount: change, from: change_address} | unspent_outputs]
  end

  defp do_consume_inputs(_change_address, unspent_outputs, remaining, _change)
       when remaining == 0.0,
       do: unspent_outputs

  # When a full unspent output is sufficient for the entire amount to spend
  # The unspent output is fully consumed and remaining part is return as changed
  defp do_consume_inputs(
         change_address,
         [%UnspentOutput{amount: amount} | rest],
         remaining,
         change
       )
       when amount >= remaining do
    do_consume_inputs(change_address, rest, 0.0, change + (amount - remaining))
  end

  # When a the unspent_output is a part of the amount to spend
  # The unspent_output is fully consumed and the iteration continue utils the the remaining amount to spend are consumed
  defp do_consume_inputs(
         change_address,
         [%UnspentOutput{amount: amount} | rest],
         remaining,
         change
       )
       when amount < remaining do
    do_consume_inputs(change_address, rest, abs(remaining - amount), change)
  end

  @doc """
  List all the addresses from transaction movements and node movements.

  Node movements public keys are hashed to produce addresses

  ## Examples

      iex> %LedgerOperations{
      ...>   transaction_movements: [
      ...>      %TransactionMovement{to: <<0, 167, 158, 251, 11, 241, 12, 240, 78, 125, 145, 72, 181, 180, 207, 109, 100,
      ...>        239, 164, 17, 54, 91, 246, 111, 162, 112, 35, 174, 44, 92, 45, 57, 213>>, amount: 5.3}
      ...>   ],
      ...>   node_movements: [
      ...>      %NodeMovement{to: <<82, 181, 95, 101, 84, 42, 93, 217, 66, 3, 234, 7, 7, 100, 88, 24, 65, 146, 60,
      ...>        116, 180, 238, 175, 16, 78, 6, 156, 147, 242, 75, 73, 160>>, amount: 0.02, roles: [] }
      ...>   ]
      ...> }
      ...> |> LedgerOperations.movement_addresses()
      [
        <<0, 167, 158, 251, 11, 241, 12, 240, 78, 125, 145, 72, 181, 180, 207, 109, 100,
          239, 164, 17, 54, 91, 246, 111, 162, 112, 35, 174, 44, 92, 45, 57, 213>>,
        <<0, 140, 71, 133, 190, 90, 57, 6, 85, 245, 172, 69, 85, 136, 244, 75, 188, 89,
          8, 246, 249, 234, 22, 211, 151, 200, 71, 141, 133, 163, 161, 142, 8>>
      ]
  """
  @spec movement_addresses(t()) :: list(binary())
  def movement_addresses(%__MODULE__{
        transaction_movements: transaction_movements,
        node_movements: node_movements
      }) do
    Enum.map(transaction_movements, & &1.to) ++ Enum.map(node_movements, &Crypto.hash(&1.to))
  end

  @doc """
  Serialize a ledger operations

  ## Examples

      iex> %LedgerOperations{
      ...>   fee: 0.1,
      ...>   transaction_movements: [
      ...>     %TransactionMovement{
      ...>       to: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      ...>           86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
      ...>       amount: 10.2
      ...>     }
      ...>   ],
      ...>   node_movements: [
      ...>     %NodeMovement{
      ...>       to: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      ...>           86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
      ...>       amount: 0.3,
      ...>       roles: [:welcome_node, :coordinator_node, :cross_validation_node, :previous_storage_node]
      ...>     }
      ...>   ],
      ...>   unspent_outputs: [
      ...>     %UnspentOutput{
      ...>       from: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      ...>           86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
      ...>       amount: 2.0
      ...>     }
      ...>   ]
      ...> }
      ...> |> LedgerOperations.serialize()
      <<
      # Fee
      63, 185, 153, 153, 153, 153, 153, 154,
      # Nb of transaction movements
      1,
      # Transaction movement recipient
      0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      # Transaction movement amount
      "@$ffffff",
      # Nb of node movements
      1,
      # Node public key
      0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      # Node reward
      63, 211, 51, 51, 51, 51, 51, 51,
      # Nb roles
      4,
      # Roles
      0, 1, 2, 3,
      # Nb of unspent outputs
      1,
      # Unspent output origin
      0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      # Unspent output amount
      64, 0, 0, 0, 0, 0, 0, 0
      >>
  """
  def serialize(%__MODULE__{
        fee: fee,
        transaction_movements: transaction_movements,
        node_movements: node_movements,
        unspent_outputs: unspent_outputs
      }) do
    bin_transaction_movements =
      transaction_movements
      |> Enum.map(&TransactionMovement.serialize/1)
      |> :erlang.list_to_binary()

    bin_node_movements =
      node_movements |> Enum.map(&NodeMovement.serialize/1) |> :erlang.list_to_binary()

    bin_unspent_outputs =
      unspent_outputs |> Enum.map(&UnspentOutput.serialize/1) |> :erlang.list_to_binary()

    <<fee::float, length(transaction_movements)::8, bin_transaction_movements::binary,
      length(node_movements)::8, bin_node_movements::binary, length(unspent_outputs)::8,
      bin_unspent_outputs::binary>>
  end

  @doc """
  Deserialize an encoded ledger operations

  ## Examples

      iex> <<63, 185, 153, 153, 153, 153, 153, 154, 1, 0, 34, 118, 242, 194, 93, 131, 130, 195,
      ...> 9, 97, 237, 220, 195, 112, 1, 54, 221, 86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47,
      ...> 158, 139, 207, "@$ffffff", 1, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112,
      ...> 1, 54, 221, 86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      ...> 63, 211, 51, 51, 51, 51, 51, 51, 4, 0, 1, 2, 3, 1, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237,
      ...> 220, 195, 112, 1, 54, 221, 86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      ...> 64, 0, 0, 0, 0, 0, 0, 0 >>
      ...> |> LedgerOperations.deserialize()
      {
        %LedgerOperations{
          fee: 0.1,
          transaction_movements: [
            %TransactionMovement{
              to: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
              amount: 10.2
            }
          ],
          node_movements: [
            %NodeMovement{
              to: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
              amount: 0.3,
              roles: [:welcome_node, :coordinator_node, :cross_validation_node, :previous_storage_node]
            }
          ],
          unspent_outputs: [
            %UnspentOutput{
              from: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
              amount: 2.0
            }
          ]
        },
        ""
      }
  """
  def deserialize(<<fee::float, nb_transaction_movements::8, rest::bitstring>>) do
    {tx_movements, rest} = reduce_transaction_movements(rest, nb_transaction_movements, [])
    <<nb_node_movements::8, rest::bitstring>> = rest
    {node_movements, rest} = reduce_node_movements(rest, nb_node_movements, [])
    <<nb_unspent_outputs::8, rest::bitstring>> = rest
    {unspent_outputs, rest} = reduce_unspent_outputs(rest, nb_unspent_outputs, [])

    {
      %__MODULE__{
        fee: fee,
        transaction_movements: tx_movements,
        node_movements: node_movements,
        unspent_outputs: unspent_outputs
      },
      rest
    }
  end

  defp reduce_transaction_movements(rest, 0, _), do: {[], rest}

  defp reduce_transaction_movements(rest, nb, acc) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp reduce_transaction_movements(rest, nb, acc) do
    {tx_movement, rest} = TransactionMovement.deserialize(rest)
    reduce_transaction_movements(rest, nb, [tx_movement | acc])
  end

  defp reduce_node_movements(rest, 0, _), do: {[], rest}

  defp reduce_node_movements(rest, nb, acc) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp reduce_node_movements(rest, nb, acc) do
    {node_movement, rest} = NodeMovement.deserialize(rest)
    reduce_node_movements(rest, nb, [node_movement | acc])
  end

  defp reduce_unspent_outputs(rest, 0, _), do: {[], rest}

  defp reduce_unspent_outputs(rest, nb, acc) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp reduce_unspent_outputs(rest, nb, acc) do
    {unspent_output, rest} = UnspentOutput.deserialize(rest)
    reduce_unspent_outputs(rest, nb, [unspent_output | acc])
  end

  @spec from_map(map()) :: t()
  def from_map(ledger_ops = %{}) do
    %__MODULE__{
      transaction_movements:
        Map.get(ledger_ops, :transaction_movements, [])
        |> Enum.map(&TransactionMovement.from_map/1),
      node_movements:
        Map.get(ledger_ops, :node_movements, [])
        |> Enum.map(&NodeMovement.from_map/1),
      unspent_outputs:
        Map.get(ledger_ops, :unspent_outputs, [])
        |> Enum.map(&UnspentOutput.from_map/1),
      fee: Map.get(ledger_ops, :fee)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{
        transaction_movements: transaction_movements,
        node_movements: node_movements,
        unspent_outputs: unspent_outputs,
        fee: fee
      }) do
    %{
      transaction_movements: Enum.map(transaction_movements, &TransactionMovement.to_map/1),
      node_movements: Enum.map(node_movements, &NodeMovement.to_map/1),
      unspent_outputs: Enum.map(unspent_outputs, &UnspentOutput.to_map/1),
      fee: fee
    }
  end

  @doc """
  Determines if the node movements are valid according to a list of nodes

  ## Examples

      iex> %LedgerOperations{
      ...>    fee: 0.5,
      ...>    node_movements: [
      ...>       %NodeMovement{to: "503EF04022CDAA3F0F402A1C2524ED3782E09F228BC16DEB1766051C86880F8D", amount: 0.0025, roles: [:welcome_node] },
      ...>       %NodeMovement{to: "F35EB8260981AC5D8268B7B323277C8FB44D73B81DCC603B0E9CEB4B406A18AD", amount: 0.0475, roles: [:coordinator_node]},
      ...>       %NodeMovement{to: "5D0AE5A5B686030AD630119F3494B4852E3990BF196C117D574FD32BEB747FC7", amount: 0.1, roles: [:cross_validation_node]},
      ...>       %NodeMovement{to: "074CA174E4763A169F714C0D37187C5AC889683B4BBE9B0859C4073A690B7DF1", amount: 0.1, roles: [:cross_validation_node]},
      ...>       %NodeMovement{to: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23", amount: 0.08333333333333333, roles: [:previous_storage_node]},
      ...>       %NodeMovement{to: "AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE", amount: 0.08333333333333333, roles: [:previous_storage_node]},
      ...>       %NodeMovement{to: "4D75266A648F6D67576E6C77138C07042077B815FB5255D7F585CD36860DA19E", amount: 0.08333333333333333, roles: [:previous_storage_node]}
      ...>    ]
      ...> }
      ...> |> LedgerOperations.valid_reward_distribution?()
      true

   When some nodes has several roles(present in the network bootstrapping phase),
   a mapping per node and per role is perform to ensure the right amount of rewards.

      iex> %LedgerOperations{
      ...>    fee: 0.5,
      ...>    node_movements: [
      ...>       %NodeMovement{to: "503EF04022CDAA3F0F402A1C2524ED3782E09F228BC16DEB1766051C86880F8D", amount: 0.25, roles: [:welcome_node, :coordinator_node, :cross_validation_node]},
      ...>       %NodeMovement{to: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23", amount: 0.08333333333333333, roles: [:previous_storage_node]},
      ...>       %NodeMovement{to: "AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE", amount: 0.08333333333333333, roles: [:previous_storage_node]},
      ...>       %NodeMovement{to: "4D75266A648F6D67576E6C77138C07042077B815FB5255D7F585CD36860DA19E", amount: 0.08333333333333333, roles: [:previous_storage_node]}
      ...>    ]
      ...> }
      ...> |> LedgerOperations.valid_reward_distribution?()
      true
  """
  @spec valid_reward_distribution?(t()) :: boolean()
  def valid_reward_distribution?(%__MODULE__{fee: fee, node_movements: node_movements}) do
    nb_cross_validation_nodes = Enum.count(node_movements, &(:cross_validation_node in &1.roles))

    cross_validation_node_reward =
      get_cross_validation_node_reward(fee, nb_cross_validation_nodes)

    nb_previous_storage_nodes = Enum.count(node_movements, &(:previous_storage_node in &1.roles))
    previous_storage_node_reward = get_previous_storage_reward(fee, nb_previous_storage_nodes)

    rewards_matrix =
      reward_per_role(fee, cross_validation_node_reward, previous_storage_node_reward)

    Enum.all?(node_movements, fn %NodeMovement{roles: roles, amount: amount} ->
      total_rewards = Enum.reduce(roles, 0.0, &(&2 + Map.get(rewards_matrix, &1)))
      amount == total_rewards
    end)
  end

  defp reward_per_role(fee, cross_validation_node_reward, previous_storage_node_reward) do
    %{
      welcome_node: get_welcome_node_reward(fee),
      coordinator_node: get_coordinator_node_reward(fee),
      cross_validation_node: cross_validation_node_reward,
      previous_storage_node: previous_storage_node_reward
    }
  end

  @doc """
  Determine if the roles in the node movements are correctly distributed:
  - one welcome node
  - one coordinator node
  - one or many cross validation nodes

  ## Examples

      iex> %LedgerOperations{
      ...>   node_movements: [
      ...>     %NodeMovement{to: "key1", amount: 0.23, roles: [:welcome_node, :coordinator_node]},
      ...>     %NodeMovement{to: "key2", amount: 0.04, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key3", amount: 0.01, roles: [:previous_storage_node]}
      ...>   ]
      ...> } |> LedgerOperations.valid_node_movements_roles?()
      true

      iex> %LedgerOperations{
      ...>   node_movements: [
      ...>     %NodeMovement{to: "key1", amount: 0.23, roles: [:welcome_node, :coordinator_node]},
      ...>     %NodeMovement{to: "key1", amount: 0.23, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key2", amount: 0.04, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key3", amount: 0.01, roles: [:previous_storage_node]}
      ...>   ]
      ...> } |> LedgerOperations.valid_node_movements_roles?()
      false
  """
  @spec valid_node_movements_roles?(t()) :: boolean()
  def valid_node_movements_roles?(%__MODULE__{node_movements: node_movements}) do
    frequencies =
      node_movements
      |> Enum.flat_map(& &1.roles)
      |> Enum.frequencies()

    with 1 <- Map.get(frequencies, :welcome_node),
         1 <- Map.get(frequencies, :coordinator_node),
         true <- Map.get(frequencies, :cross_validation_nodes) >= 1 do
      true
    else
      _ ->
        false
    end
  end

  @doc """
  Determine if the cross validation node movements public keys are the good one from a list of cross validation node public keys

  ## Examples

      iex> %LedgerOperations{
      ...>   node_movements: [
      ...>     %NodeMovement{to: "key1", amount: 0.01, roles: [:welcome_node]},
      ...>     %NodeMovement{to: "key2", amount: 0.30, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key3", amount: 0.15, roles: [:cross_validation_node]}
      ...>   ]
      ...> } |> LedgerOperations.valid_node_movements_cross_validation_nodes?(["key3"])
      true
  """
  @spec valid_node_movements_cross_validation_nodes?(t(), list(Crypto.key())) :: boolean()
  def valid_node_movements_cross_validation_nodes?(
        %__MODULE__{node_movements: node_movements},
        cross_validation_node_public_keys
      ) do
    node_movements
    |> Enum.filter(&(&1.to in cross_validation_node_public_keys))
    |> Enum.all?(&(:cross_validation_node in &1.roles))
  end

  @doc """
  Determine if the node movements with previous storage node role are the list of previous storage nodes public keys

  ## Examples

      iex> %LedgerOperations{
      ...>   node_movements: [
      ...>     %NodeMovement{to: "key1", amount: 0.01, roles: [:welcome_node]},
      ...>     %NodeMovement{to: "key2", amount: 0.30, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key3", amount: 0.15, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key4", amount: 0.80, roles: [:previous_storage_nodes]}
      ...>   ]
      ...> } |> LedgerOperations.valid_node_movements_previous_storage_nodes?(["key10", "key4", "key8"])
      true

      iex> %LedgerOperations{
      ...>   node_movements: [
      ...>     %NodeMovement{to: "key1", amount: 0.01, roles: [:welcome_node]},
      ...>     %NodeMovement{to: "key2", amount: 0.30, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key3", amount: 0.15, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key4", amount: 0.80, roles: [:previous_storage_nodes]},
      ...>     %NodeMovement{to: "key22", amount: 0.80, roles: [:previous_storage_node]}
      ...>   ]
      ...> } |> LedgerOperations.valid_node_movements_previous_storage_nodes?(["key10", "key4", "key8"])
      false
  """
  @spec valid_node_movements_previous_storage_nodes?(t(), list(Crypto.key())) :: boolean()
  def valid_node_movements_previous_storage_nodes?(
        %__MODULE__{node_movements: node_movements},
        previous_storage_node_public_keys
      ) do
    node_movements
    |> Enum.filter(&(:previous_storage_node in &1.roles))
    |> Enum.all?(&(&1.to in previous_storage_node_public_keys))
  end

  @doc """
  Determine if the node movements involve a node public key with a given role

  ## Examples

      iex> %LedgerOperations{
      ...>   node_movements: [
      ...>     %NodeMovement{to: "key1", amount: 0.30, roles: [:welcome_node]},
      ...>     %NodeMovement{to: "key2", amount: 0.43, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key3", amount: 0.2, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key4", amount: 0.1, roles: [:previous_storage_node]}
      ...>   ]
      ...> }
      ...> |> LedgerOperations.has_node_movement_with_role?("key2", :coordinator_node)
      true

      iex> %LedgerOperations{
      ...>   node_movements: [
      ...>     %NodeMovement{to: "key1", amount: 0.30, roles: [:welcome_node]},
      ...>     %NodeMovement{to: "key2", amount: 0.43, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key3", amount: 0.2, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key4", amount: 0.1, roles: [:previous_storage_node]}
      ...>   ]
      ...> }
      ...> |> LedgerOperations.has_node_movement_with_role?("other node", :coordinator_node)
      false

      iex> %LedgerOperations{
      ...>   node_movements: [
      ...>     %NodeMovement{to: "key1", amount: 0.30, roles: [:welcome_node]},
      ...>     %NodeMovement{to: "key2", amount: 0.43, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key3", amount: 0.2, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key4", amount: 0.1, roles: [:previous_storage_node]}
      ...>   ]
      ...> }
      ...> |> LedgerOperations.has_node_movement_with_role?("key1", :coordinator_node)
      false
  """
  @spec has_node_movement_with_role?(t(), Crypto.key(), NodeMovement.role()) :: boolean()
  def has_node_movement_with_role?(
        %__MODULE__{node_movements: node_movements},
        node_public_key,
        node_role
      ) do
    Enum.any?(node_movements, &(&1.to == node_public_key and node_role in &1.roles))
  end
end
