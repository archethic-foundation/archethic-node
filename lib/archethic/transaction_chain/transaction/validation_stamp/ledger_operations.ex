defmodule ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations do
  @moduledoc """
  Represents the ledger operations defined during the transaction mining regarding the network movements:
  - transaction movements
  - node rewards
  - unspent outputs
  - transaction fee
  """

  @unit_uco 100_000_000

  # 0.5%
  @storage_node_rate 50_000_000
  # 0.4%
  @cross_validation_node_rate 40_000_000
  # 0.1%
  @coordinator_rate 10_000_000
  # 0.1%
  @network_pool_rate 10_000_000

  defstruct transaction_movements: [],
            node_movements: [],
            unspent_outputs: [],
            fee: 0

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionInput

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
          fee: non_neg_integer()
        }

  @burning_address <<0::8, 0::256>>

  @doc """
  Return the address used for the burning
  """
  @spec burning_address() :: Crypto.versioned_hash()
  def burning_address, do: @burning_address

  @doc """
  Build some ledger operations from a specific transaction

  ## Examples

      iex> LedgerOperations.from_transaction(%LedgerOperations{},
      ...>   %Transaction{
      ...>     address: "@NFT2",
      ...>     type: :nft,
      ...>     data: %TransactionData{content: "initial supply: 1000"}
      ...>   }
      ...> )
      %LedgerOperations{
          unspent_outputs: [%UnspentOutput{from: "@NFT2", amount: 100_000_000_000, type: {:NFT, "@NFT2"}}]
      }
  """
  @spec from_transaction(t(), Transaction.t()) :: t()
  def from_transaction(ops = %__MODULE__{}, %Transaction{
        address: address,
        type: :nft,
        data: %TransactionData{content: content}
      }) do
    [[match | _]] = Regex.scan(~r/(?<=initial supply:).*\d/mi, content)

    {initial_supply, _} =
      match
      |> String.trim()
      |> String.replace(" ", "")
      |> Integer.parse()

    %{
      ops
      | unspent_outputs: [
          %UnspentOutput{from: address, amount: initial_supply * @unit_uco, type: {:NFT, address}}
        ]
    }
  end

  def from_transaction(ops = %__MODULE__{}, %Transaction{}), do: ops

  @doc """
  Create node rewards and movements based on the transaction fee by distributing it using the different rates
  for each individual actor: coordinator node, cross validation node, previous storage node

  10% of the transaction's fee are burnt dedicated to the network pool

  ## Examples

      iex> %LedgerOperations{ fee: 50_000_000} # 0.5 UCO
      ...> |> LedgerOperations.distribute_rewards(
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
         fee: 50_000_000,
         transaction_movements: [ %TransactionMovement { to: <<0::8, 0::256>>, amount: 5_000_000, type: :UCO} ],
         node_movements: [
            %NodeMovement{to: "074CA174E4763A169F714C0D37187C5AC889683B4BBE9B0859C4073A690B7DF1", amount: 10_000_000, roles: [:cross_validation_node] },
            %NodeMovement{to: "4D75266A648F6D67576E6C77138C07042077B815FB5255D7F585CD36860DA19E", amount: 8_333_333, roles: [:previous_storage_node]},
            %NodeMovement{to: "5D0AE5A5B686030AD630119F3494B4852E3990BF196C117D574FD32BEB747FC7", amount: 10_000_000, roles: [:cross_validation_node]},
            %NodeMovement{to: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23", amount: 8_333_333, roles: [:previous_storage_node]},
            %NodeMovement{to: "AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE", amount: 8_333_333, roles: [:previous_storage_node]},
            %NodeMovement{to: "F35EB8260981AC5D8268B7B323277C8FB44D73B81DCC603B0E9CEB4B406A18AD", amount: 5_000_000, roles: [:coordinator_node]},
         ]
      }

    When some nodes has several roles (present in the network bootstrapping phase),
    a mapping per node and per role is perform to ensure the right amount of rewards.

      iex> %LedgerOperations{ fee: 50_000_000}
      ...> |> LedgerOperations.distribute_rewards(
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
         fee: 50_000_000,
         transaction_movements: [ %TransactionMovement { to: <<0::8, 0::256>>, amount: 5_000_000, type: :UCO} ],
         node_movements: [
            %NodeMovement{to: "4D75266A648F6D67576E6C77138C07042077B815FB5255D7F585CD36860DA19E", amount: 8_333_333, roles: [:previous_storage_node]},
            %NodeMovement{to: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23", amount: 23_333_333, roles: [:coordinator_node, :cross_validation_node, :previous_storage_node] },
            %NodeMovement{to: "AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE", amount: 8_333_333, roles: [:previous_storage_node] }
         ]
      }
  """
  @spec distribute_rewards(t(), Node.t(), list(Node.t()), list(Node.t())) ::
          t()
  def distribute_rewards(
        ops = %__MODULE__{fee: fee},
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

    ops
    |> Map.update!(
      :transaction_movements,
      &[
        %TransactionMovement{
          to: @burning_address,
          amount: get_network_pool_reward(fee),
          type: :UCO
        }
        | &1
      ]
    )
    |> Map.put(:node_movements, node_movements)
  end

  defp sum_rewards(_, _, acc \\ %{})

  defp sum_rewards([{public_key, roles} | tail], rewards_by_role, acc) do
    sum_node_rewards = Enum.reduce(roles, 0, &(&2 + Map.get(rewards_by_role, &1)))
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
  Return the reward for the network pool based on the fee and its rate

  The allocation for the network represents 10%

  ## Examples

      iex> LedgerOperations.get_network_pool_reward(100_000_000)
      10_000_000
  """
  @spec get_network_pool_reward(fee :: non_neg_integer()) :: non_neg_integer()
  def get_network_pool_reward(fee), do: div(fee * @network_pool_rate, @unit_uco)

  @doc """
  Return the reward for the coordinator node based on the fee and its rate

  The allocation for coordinator represents 10%

  ## Examples

      iex> LedgerOperations.get_coordinator_node_reward(100_000_000)
      10_000_000
  """
  @spec get_coordinator_node_reward(fee :: non_neg_integer()) :: non_neg_integer()
  def get_coordinator_node_reward(fee), do: div(fee * @coordinator_rate, @unit_uco)

  @doc """
  Return the reward for each cross validation node based on the fee, the rate and the number of cross validation nodes

  The allocation for the entire cross validation nodes represents 40% of the fee

  ## Examples

      iex> LedgerOperations.get_cross_validation_node_reward(100_000_000, 2)
      20_000_000
  """
  @spec get_cross_validation_node_reward(
          fee :: non_neg_integer(),
          nb_cross_validation_nodes :: non_neg_integer()
        ) :: non_neg_integer()
  def get_cross_validation_node_reward(fee, nb_cross_validation_nodes) do
    (fee * @cross_validation_node_rate)
    |> div(@unit_uco)
    |> div(nb_cross_validation_nodes)
  end

  @doc """
  Return the reward for each previous storage node based on the fee, its rate and the number of storage nodes

  The allocation for the entire previous storages nodes represents 50% of the fee

  ## Examples

      iex> LedgerOperations.get_previous_storage_reward(100_000_000, 5)
      10_000_000

      iex> LedgerOperations.get_previous_storage_reward(100_000_000, 0)
      0
  """
  @spec get_previous_storage_reward(
          fee :: non_neg_integer(),
          nb_previous_storage_nodes :: non_neg_integer()
        ) :: non_neg_integer()
  def get_previous_storage_reward(_fee, 0), do: 0

  def get_previous_storage_reward(fee, nb_previous_storage_nodes) do
    (fee * @storage_node_rate)
    |> div(@unit_uco)
    |> div(nb_previous_storage_nodes)
  end

  @doc """
  Returns the amount to spend from the transaction movements and the fee

  ## Examples

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 2_000_000_000, type: {:NFT, "@TomNFT"}},
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.total_to_spend()
      %{ uco: 1_297_000_000, nft: %{ "@TomNFT" => 2_000_000_000 } }
  """
  @spec total_to_spend(t()) :: %{
          :uco => non_neg_integer(),
          :nft => %{binary() => non_neg_integer()}
        }
  def total_to_spend(%__MODULE__{transaction_movements: transaction_movements, fee: fee}) do
    transaction_movements
    |> Enum.reject(&(&1.to == @burning_address))
    |> ledger_balances(%{uco: fee, nft: %{}})
  end

  defp ledger_balances(movements, acc \\ %{uco: 0, nft: %{}}) do
    Enum.reduce(movements, acc, fn
      %{type: :UCO, amount: amount}, acc ->
        Map.update!(acc, :uco, &(&1 + amount))

      %{type: {:NFT, nft_address}, amount: amount}, acc ->
        update_in(acc, [:nft, Access.key(nft_address, 0)], &(&1 + amount))

      %{type: :call}, acc ->
        acc
    end)
  end

  @doc """
  Determine if the funds are sufficient with the given unspent outputs for total of uco to spend

  ## Examples

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Tom4", amount: 500_000_000, type: {:NFT, "@BobNFT"}}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.sufficient_funds?([])
      false

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Tom4", amount: 500_000_000, type: {:NFT, "@BobNFT"}}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.sufficient_funds?([
      ...>     %UnspentOutput{from: "@Charlie5", amount: 3_000_000_000, type: :UCO},
      ...>     %UnspentOutput{from: "@Bob4", amount: 1_000_000_000, type: {:NFT, "@BobNFT"}}
      ...> ])
      true

      iex> %LedgerOperations{
      ...>    transaction_movements: [],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.sufficient_funds?([
      ...>     %UnspentOutput{from: "@Charlie5", amount: 3_000_000_000, type: :UCO},
      ...>     %UnspentOutput{from: "@Bob4", amount: 10_000_000_000, type: {:NFT, "@BobNFT"}}
      ...> ])
      true
  """
  @spec sufficient_funds?(t(), list(UnspentOutput.t() | TransactionInput.t())) :: boolean()
  def sufficient_funds?(operations = %__MODULE__{}, inputs) when is_list(inputs) do
    %{uco: uco_balance, nft: nfts_received} = ledger_balances(inputs)
    %{uco: uco_to_spend, nft: nfts_to_spend} = total_to_spend(operations)
    uco_balance >= uco_to_spend and sufficient_nfts?(nfts_received, nfts_to_spend)
  end

  defp sufficient_nfts?(nfts_received = %{}, nft_to_spend = %{})
       when map_size(nfts_received) == 0 and map_size(nft_to_spend) > 0,
       do: false

  defp sufficient_nfts?(_nfts_received, nfts_to_spend) when map_size(nfts_to_spend) == 0, do: true

  defp sufficient_nfts?(nfts_received, nfts_to_spend) do
    Enum.all?(nfts_to_spend, fn {nft_address, amount_to_spend} ->
      case Map.get(nfts_received, nft_address) do
        nil ->
          false

        recv_amount ->
          recv_amount >= amount_to_spend
      end
    end)
  end

  @doc """
  Use the necessary inputs to satisfy the uco amount to spend

  The remaining unspent outputs will go to the change address

  ## Examples

    # When a single unspent output is sufficient to satisfy the transaction movements

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.consume_inputs("@Alice2", [
      ...>    %UnspentOutput{from: "@Bob3", amount: 2_000_000_000, type: :UCO}
      ...> ])
      %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
            %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO}
          ],
          fee: 40_000_000,
          node_movements: [],
          unspent_outputs: [
            %UnspentOutput{from: "@Alice2", amount: 703_000_000, type: :UCO}
          ]
      }

    # When multiple little unspent output are sufficient to satisfy the transaction movements

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
      ...>      %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.consume_inputs("@Alice2", [
      ...>    %UnspentOutput{from: "@Bob3", amount: 500_000_000, type: :UCO},
      ...>    %UnspentOutput{from: "@Tom4", amount: 700_000_000, type: :UCO},
      ...>    %UnspentOutput{from: "@Christina", amount: 400_000_000, type: :UCO},
      ...>    %UnspentOutput{from: "@Hugo", amount: 800_000_000, type: :UCO}
      ...> ])
      %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Bob4", amount: 1_040_000_000, type: :UCO},
            %TransactionMovement{to: "@Charlie2", amount: 217_000_000, type: :UCO},
          ],
          fee: 40_000_000,
          node_movements: [],
          unspent_outputs: [
            %UnspentOutput{from: "@Alice2", amount: 1_103_000_000, type: :UCO},
          ]
      }

    # When using NFT unspent outputs are sufficient to satisfy the transaction movements

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_000_000_000, type: {:NFT, "@CharlieNFT"}}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.consume_inputs("@Alice2", [
      ...>    %UnspentOutput{from: "@Charlie1", amount: 200_000_000, type: :UCO},
      ...>    %UnspentOutput{from: "@Bob3", amount: 1_200_000_000, type: {:NFT, "@CharlieNFT"}}
      ...> ])
      %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Bob4", amount: 1_000_000_000, type: {:NFT, "@CharlieNFT"}}
          ],
          fee: 40_000_000,
          node_movements: [],
          unspent_outputs: [
            %UnspentOutput{from: "@Alice2", amount: 160_000_000, type: :UCO},
            %UnspentOutput{from: "@Alice2", amount: 200_000_000, type: {:NFT, "@CharlieNFT"}}
          ]
      }

    #  When multiple NFT unspent outputs are sufficient to satisfy the transaction movements

      iex> %LedgerOperations{
      ...>    transaction_movements: [
      ...>      %TransactionMovement{to: "@Bob4", amount: 1_000_000_000, type: {:NFT, "@CharlieNFT"}}
      ...>    ],
      ...>    fee: 40_000_000
      ...> }
      ...> |> LedgerOperations.consume_inputs("@Alice2", [
      ...>    %UnspentOutput{from: "@Charlie1", amount: 200_000_000, type: :UCO},
      ...>    %UnspentOutput{from: "@Bob3", amount: 500_000_000, type: {:NFT, "@CharlieNFT"}},
      ...>    %UnspentOutput{from: "@Hugo5", amount: 700_000_000, type: {:NFT, "@CharlieNFT"}},
      ...>    %UnspentOutput{from: "@Tom1", amount: 700_000_000, type: {:NFT, "@CharlieNFT"}}
      ...> ])
      %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Bob4", amount: 1_000_000_000, type: {:NFT, "@CharlieNFT"}}
          ],
          fee: 40_000_000,
          node_movements: [],
          unspent_outputs: [
            %UnspentOutput{from: "@Alice2", amount: 160_000_000, type: :UCO},
            %UnspentOutput{from: "@Alice2", amount: 900_000_000, type: {:NFT, "@CharlieNFT"}}
          ]
      }
  """
  @spec consume_inputs(
          ledger_operations :: t(),
          change_address :: binary(),
          inputs :: list(UnspentOutput.t() | TransactionInput.t())
        ) ::
          t()
  def consume_inputs(ops = %__MODULE__{}, change_address, inputs)
      when is_binary(change_address) and is_list(inputs) do
    if sufficient_funds?(ops, inputs) do
      %{uco: uco_balance, nft: nfts_received} = ledger_balances(inputs)
      %{uco: uco_to_spend, nft: nfts_to_spend} = total_to_spend(ops)

      new_unspent_outputs = [
        %UnspentOutput{from: change_address, amount: uco_balance - uco_to_spend, type: :UCO}
        | new_nft_unspent_outputs(nfts_received, nfts_to_spend, change_address)
      ]

      Map.update!(ops, :unspent_outputs, &(new_unspent_outputs ++ &1))
    else
      ops
    end
  end

  defp new_nft_unspent_outputs(nfts_received, nfts_to_spend, change_address) do
    Enum.reduce(nfts_to_spend, [], fn {nft_address, amount_to_spend}, acc ->
      case Map.get(nfts_received, nft_address) do
        nil ->
          acc

        recv_amount ->
          [
            %UnspentOutput{
              from: change_address,
              amount: recv_amount - amount_to_spend,
              type: {:NFT, nft_address}
            }
            | acc
          ]
      end
    end)
  end

  @doc """
  List all the addresses from transaction movements and node movements.

  Node movements public keys are used to determine the node addresses
  """
  @spec movement_addresses(t()) :: list(binary())
  def movement_addresses(%__MODULE__{
        transaction_movements: transaction_movements,
        node_movements: node_movements
      }) do
    node_addresses =
      node_movements
      |> Enum.map(fn %NodeMovement{to: public_key} ->
        %Node{reward_address: address} = P2P.get_node_info!(public_key)
        address
      end)

    transaction_addresses =
      transaction_movements
      |> Enum.reject(&(&1.to == @burning_address))
      |> Enum.map(& &1.to)

    transaction_addresses ++ node_addresses
  end

  @doc """
  Serialize a ledger operations

  ## Examples

      iex> %LedgerOperations{
      ...>   fee: 10_000_000,
      ...>   transaction_movements: [
      ...>     %TransactionMovement{
      ...>       to: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      ...>           86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
      ...>       amount: 102_000_000,
      ...>       type: :UCO
      ...>     },
      ...>     %TransactionMovement{to: <<0::8, 0::256>> , amount: 1_000_000, type: :UCO}
      ...>   ],
      ...>   node_movements: [
      ...>     %NodeMovement{
      ...>       to: <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      ...>           86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
      ...>       amount: 9_000_000,
      ...>       roles: [:coordinator_node, :cross_validation_node, :previous_storage_node]
      ...>     },
      ...>   ],
      ...>   unspent_outputs: [
      ...>     %UnspentOutput{
      ...>       from: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      ...>           86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
      ...>       amount: 200_000_000,
      ...>       type: :UCO
      ...>     }
      ...>   ]
      ...> }
      ...> |> LedgerOperations.serialize()
      <<
      # Fee (0.1 UCO)
      0, 0, 0, 0, 0, 152, 150, 128,
      # Nb of transaction movements
      2,
      # Transaction movement recipient
      0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      # Transaction movement amount (1.2 UCO)
      0, 0, 0, 0, 6, 20, 101, 128,
      # Transaction movement type (UCO)
      0,
      # Network pool burning address
      0::8, 0::256,
      # Amount of fee burnt (0.01)
      0, 0, 0, 0, 0, 15, 66, 64,
      # Type of movement
      0,
      # Nb of node movements
      1,
      # Node public key
      0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      # Node reward (0.09 UCO)
      0, 0, 0, 0, 0, 137, 84, 64,
      # Nb roles
      3,
      # Roles
      0, 1, 2,
      # Nb of unspent outputs
      1,
      # Unspent output origin
      0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
      86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      # Unspent output amount (2 UCO)
      0, 0, 0, 0, 11, 235, 194, 0,
      # Unspent output type (UCO)
      0,
      # Unspent output reward?
      0
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

    <<fee::64, length(transaction_movements)::8, bin_transaction_movements::binary,
      length(node_movements)::8, bin_node_movements::binary, length(unspent_outputs)::8,
      bin_unspent_outputs::binary>>
  end

  @doc """
  Deserialize an encoded ledger operations

  ## Examples

      iex> <<0, 0, 0, 0, 0, 152, 150, 128, 2, 
      ...> 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221, 86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207, 
      ...> 0, 0, 0, 0, 60, 203, 247, 0, 0,
      ...> 0, 0::256, 0, 0, 0, 0, 0, 15, 66, 64, 0,
      ...> 1, 0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112,
      ...> 1, 54, 221, 86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207, 
      ...> 0, 0, 0, 0, 0, 137, 84, 64,
      ...> 3, 0, 1, 2, 
      ...> 1, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237,
      ...> 220, 195, 112, 1, 54, 221, 86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207,
      ...> 0, 0, 0, 0, 11, 235, 194, 0, 0, 0>>
      ...> |> LedgerOperations.deserialize()
      {
        %LedgerOperations{
          fee: 10_000_000,
          transaction_movements: [
            %TransactionMovement{
              to: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
              amount: 1_020_000_000,
              type: :UCO
            },
            %TransactionMovement {
              to: <<0::8, 0::256>>,
              amount: 1_000_000,
              type: :UCO
            }
          ],
          node_movements: [
            %NodeMovement{
              to: <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
              amount: 9_000_000,
              roles: [:coordinator_node, :cross_validation_node, :previous_storage_node]
            }
          ],
          unspent_outputs: [
            %UnspentOutput{
              from: <<0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
              amount: 200_000_000,
              type: :UCO,
              reward?: false
            }
          ]
        },
        ""
      }
  """
  def deserialize(<<fee::64, nb_transaction_movements::8, rest::bitstring>>) do
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
      ...>    fee: 50_000_000,
      ...>    transaction_movements: [%TransactionMovement{to: <<0::8, 0::256>>, amount: 5_000_000, type: :UCO}],  
      ...>    node_movements: [
      ...>       %NodeMovement{to: "F35EB8260981AC5D8268B7B323277C8FB44D73B81DCC603B0E9CEB4B406A18AD", amount: 5_000_000, roles: [:coordinator_node]},
      ...>       %NodeMovement{to: "5D0AE5A5B686030AD630119F3494B4852E3990BF196C117D574FD32BEB747FC7", amount: 10_000_000, roles: [:cross_validation_node]},
      ...>       %NodeMovement{to: "074CA174E4763A169F714C0D37187C5AC889683B4BBE9B0859C4073A690B7DF1", amount: 10_000_000, roles: [:cross_validation_node]},
      ...>       %NodeMovement{to: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23", amount: 8_333_333, roles: [:previous_storage_node]},
      ...>       %NodeMovement{to: "AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE", amount: 8_333_333, roles: [:previous_storage_node]},
      ...>       %NodeMovement{to: "4D75266A648F6D67576E6C77138C07042077B815FB5255D7F585CD36860DA19E", amount: 8_333_333, roles: [:previous_storage_node]}
      ...>    ]
      ...> }
      ...> |> LedgerOperations.valid_reward_distribution?()
      true

   When some nodes has several roles(present in the network bootstrapping phase),
   a mapping per node and per role is perform to ensure the right amount of rewards.

      iex> %LedgerOperations{
      ...>    fee: 50_000_000,
      ...>    transaction_movements: [%TransactionMovement{to: <<0::8, 0::256>>, amount: 5_000_000, type: :UCO}],  
      ...>    node_movements: [
      ...>       %NodeMovement{to: "503EF04022CDAA3F0F402A1C2524ED3782E09F228BC16DEB1766051C86880F8D", amount: 25_000_000, roles: [:coordinator_node, :cross_validation_node]},
      ...>       %NodeMovement{to: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23", amount: 8_333_333, roles: [:previous_storage_node]},
      ...>       %NodeMovement{to: "AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE", amount: 8_333_333, roles: [:previous_storage_node]},
      ...>       %NodeMovement{to: "4D75266A648F6D67576E6C77138C07042077B815FB5255D7F585CD36860DA19E", amount: 8_333_333, roles: [:previous_storage_node]}
      ...>    ]
      ...> }
      ...> |> LedgerOperations.valid_reward_distribution?()
      true
  """
  @spec valid_reward_distribution?(t()) :: boolean()
  def valid_reward_distribution?(%__MODULE__{
        fee: fee,
        node_movements: node_movements,
        transaction_movements: transaction_movements
      }) do
    nb_cross_validation_nodes = Enum.count(node_movements, &(:cross_validation_node in &1.roles))

    cross_validation_node_reward =
      get_cross_validation_node_reward(fee, nb_cross_validation_nodes)

    nb_previous_storage_nodes = Enum.count(node_movements, &(:previous_storage_node in &1.roles))
    previous_storage_node_reward = get_previous_storage_reward(fee, nb_previous_storage_nodes)

    rewards_matrix =
      reward_per_role(fee, cross_validation_node_reward, previous_storage_node_reward)

    valid_node_movements? =
      Enum.all?(node_movements, fn %NodeMovement{roles: roles, amount: amount} ->
        total_rewards = Enum.reduce(roles, 0, &(&2 + Map.get(rewards_matrix, &1)))
        amount == total_rewards
      end)

    valid_network_pool_reward? =
      Enum.any?(
        transaction_movements,
        &(&1.to == @burning_address and &1.amount == get_network_pool_reward(fee) and
            &1.type == :UCO)
      )

    valid_network_pool_reward? and valid_node_movements?
  end

  defp reward_per_role(fee, cross_validation_node_reward, previous_storage_node_reward) do
    %{
      coordinator_node: get_coordinator_node_reward(fee),
      cross_validation_node: cross_validation_node_reward,
      previous_storage_node: previous_storage_node_reward
    }
  end

  @doc """
  Determine if the roles in the node movements are correctly distributed:
  - one coordinator node
  - one or many cross validation nodes

  ## Examples

      iex> %LedgerOperations{
      ...>   node_movements: [
      ...>     %NodeMovement{to: "key1", amount: 23_000_000, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key2", amount: 4_000_000, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key3", amount: 1_000_000, roles: [:previous_storage_node]}
      ...>   ]
      ...> } |> LedgerOperations.valid_node_movements_roles?()
      true

      iex> %LedgerOperations{
      ...>   node_movements: [
      ...>     %NodeMovement{to: "key1", amount: 23_000_000, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key1", amount: 23_000_000, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key2", amount: 4_000_000, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key3", amount: 1_000_000, roles: [:previous_storage_node]}
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

    with 1 <- Map.get(frequencies, :coordinator_node),
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
      ...>     %NodeMovement{to: "key2", amount: 30_000_000, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key3", amount: 15_000_000, roles: [:cross_validation_node]}
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
      ...>     %NodeMovement{to: "key2", amount: 30_000_000, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key3", amount: 10_000_000, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key4", amount: 80_000_000, roles: [:previous_storage_nodes]}
      ...>   ]
      ...> } |> LedgerOperations.valid_node_movements_previous_storage_nodes?(["key10", "key4", "key8"])
      true

      iex> %LedgerOperations{
      ...>   node_movements: [
      ...>     %NodeMovement{to: "key2", amount: 30_000_000, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key3", amount: 15_000_000, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key4", amount: 80_000_000, roles: [:previous_storage_nodes]},
      ...>     %NodeMovement{to: "key22", amount: 80_000_000, roles: [:previous_storage_node]}
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
      ...>     %NodeMovement{to: "key2", amount: 43_000_000, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key3", amount: 20_000_000, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key4", amount: 10_000_000, roles: [:previous_storage_node]}
      ...>   ]
      ...> }
      ...> |> LedgerOperations.has_node_movement_with_role?("key2", :coordinator_node)
      true

      iex> %LedgerOperations{
      ...>   node_movements: [
      ...>     %NodeMovement{to: "key2", amount: 43_000_000, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key3", amount: 20_000_000, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key4", amount: 10_000_000, roles: [:previous_storage_node]}
      ...>   ]
      ...> }
      ...> |> LedgerOperations.has_node_movement_with_role?("other node", :coordinator_node)
      false

      iex> %LedgerOperations{
      ...>   node_movements: [
      ...>     %NodeMovement{to: "key2", amount: 43_000_000, roles: [:coordinator_node]},
      ...>     %NodeMovement{to: "key3", amount: 20_000_000, roles: [:cross_validation_node]},
      ...>     %NodeMovement{to: "key4", amount: 10_000_000, roles: [:previous_storage_node]}
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

  @doc """
  Determines if the transaction movements are valid at a given time
  """
  @spec valid_transaction_movements?(t(), list(TransactionMovement.t()), DateTime.t()) ::
          boolean()
  def valid_transaction_movements?(
        %__MODULE__{fee: fee, transaction_movements: resolved_transaction_movements},
        tx_movements,
        timestamp = %DateTime{}
      ) do
    expected_movements = [
      %TransactionMovement{to: @burning_address, amount: get_network_pool_reward(fee), type: :UCO}
      | resolve_transaction_movements(tx_movements, timestamp)
    ]

    Enum.all?(resolved_transaction_movements, &(&1 in expected_movements))
  end

  @doc """
  Resolve the last transaction addresses from the transaction movements
  """
  @spec resolve_transaction_movements(list(TransactionMovement.t()), DateTime.t()) ::
          list(TransactionMovement.t())
  def resolve_transaction_movements(
        tx_movements,
        timestamp = %DateTime{}
      ) do
    tx_movements
    |> Task.async_stream(
      fn mvt = %TransactionMovement{to: to} ->
        %{mvt | to: TransactionChain.resolve_last_address(to, timestamp)}
      end,
      on_timeout: :kill_task
    )
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Enum.into([], fn {:ok, res} -> res end)
  end
end
