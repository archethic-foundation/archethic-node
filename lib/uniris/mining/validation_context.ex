defmodule Uniris.Mining.ValidationContext do
  @moduledoc """
  Represent the transaction validation workflow state
  """

  defstruct [
    :transaction,
    :previous_transaction,
    :welcome_node,
    :coordinator_node,
    :cross_validation_nodes,
    :validation_stamp,
    unspent_outputs: [],
    cross_validation_stamps: [],
    cross_validation_nodes_confirmation: <<>>,
    validation_nodes_view: <<>>,
    chain_storage_nodes: [],
    chain_storage_nodes_view: <<>>,
    beacon_storage_nodes: [],
    beacon_storage_nodes_view: <<>>,
    sub_replication_tree: %{
      chain: <<>>,
      beacon: <<>>,
      IO: <<>>
    },
    full_replication_tree: %{
      chain: [],
      beacon: [],
      IO: []
    },
    io_storage_nodes: [],
    previous_storage_nodes: [],
    replication_nodes_confirmation: %{
      chain: <<>>,
      beacon: <<>>,
      IO: <<>>
    },
    valid_pending_transaction?: false
  ]

  alias Uniris.Contracts

  alias Uniris.Crypto

  alias Uniris.Election

  alias Uniris.Mining.ProofOfWork

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.CrossValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionChain.TransactionData

  alias Uniris.Utils

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          previous_transaction: nil | Transaction.t(),
          unspent_outputs: list(UnspentOutput.t()),
          welcome_node: Node.t(),
          coordinator_node: Node.t(),
          cross_validation_nodes: list(Node.t()),
          previous_storage_nodes: list(Node.t()),
          chain_storage_nodes: list(Node.t()),
          beacon_storage_nodes: list(Node.t()),
          io_storage_nodes: list(Node.t()),
          cross_validation_nodes_confirmation: bitstring(),
          validation_stamp: nil | ValidationStamp.t(),
          full_replication_tree: %{
            chain: list(bitstring()),
            beacon: list(bitstring()),
            IO: list(bitstring())
          },
          sub_replication_tree: %{
            chain: bitstring(),
            beacon: bitstring(),
            IO: bitstring()
          },
          cross_validation_stamps: list(CrossValidationStamp.t()),
          replication_nodes_confirmation: %{
            chain: bitstring(),
            beacon: bitstring(),
            IO: bitstring()
          },
          validation_nodes_view: bitstring(),
          chain_storage_nodes_view: bitstring(),
          beacon_storage_nodes_view: bitstring(),
          valid_pending_transaction?: boolean()
        }

  @doc """
  Create a new mining context.

  It extracts coordinator and cross validation nodes from the validation nodes list

  It computes P2P views based on the cross validation nodes, beacon and chain storage nodes availability

  ## Examples

      iex> ValidationContext.new(
      ...>   transaction: %Transaction{},
      ...>   welcome_node: %Node{last_public_key: "key1", availability_history: <<1::1>>},
      ...>   validation_nodes: [%Node{last_public_key: "key2", availability_history: <<1::1>>}, %Node{last_public_key: "key3", availability_history: <<1::1>>}],
      ...>   chain_storage_nodes: [%Node{last_public_key: "key4", availability_history: <<1::1>>}, %Node{last_public_key: "key5", availability_history: <<1::1>>}],
      ...>   beacon_storage_nodes: [%Node{last_public_key: "key6", availability_history: <<1::1>>}, %Node{last_public_key: "key7", availability_history: <<1::1>>}])
      %ValidationContext{
        transaction: %Transaction{},
        welcome_node: %Node{last_public_key: "key1", availability_history: <<1::1>>},
        coordinator_node: %Node{last_public_key: "key2", availability_history: <<1::1>>},
        cross_validation_nodes: [%Node{last_public_key: "key3", availability_history: <<1::1>>}],
        cross_validation_nodes_confirmation: <<0::1>>,
        chain_storage_nodes: [%Node{last_public_key: "key4", availability_history: <<1::1>>}, %Node{last_public_key: "key5", availability_history: <<1::1>>}],
        beacon_storage_nodes: [%Node{last_public_key: "key6", availability_history: <<1::1>>}, %Node{last_public_key: "key7", availability_history: <<1::1>>}]
      }
  """
  @spec new(opts :: Keyword.t()) :: t()
  def new(attrs \\ []) when is_list(attrs) do
    {coordinator_node, cross_validation_nodes} =
      case Keyword.get(attrs, :validation_nodes) do
        [coordinator_node | []] ->
          {coordinator_node, [coordinator_node]}

        [coordinator_node | cross_validation_nodes] ->
          {coordinator_node, cross_validation_nodes}
      end

    nb_cross_validations_nodes = length(cross_validation_nodes)

    tx = Keyword.get(attrs, :transaction)
    welcome_node = Keyword.get(attrs, :welcome_node)
    chain_storage_nodes = Keyword.get(attrs, :chain_storage_nodes)
    beacon_storage_nodes = Keyword.get(attrs, :beacon_storage_nodes)

    %__MODULE__{
      transaction: tx,
      welcome_node: welcome_node,
      coordinator_node: coordinator_node,
      cross_validation_nodes: cross_validation_nodes,
      cross_validation_nodes_confirmation: <<0::size(nb_cross_validations_nodes)>>,
      chain_storage_nodes: chain_storage_nodes,
      beacon_storage_nodes: beacon_storage_nodes
    }
  end

  @doc """
  Set the pending transaction validation flag
  """
  @spec set_pending_transaction_validation(t(), boolean()) :: t()
  def set_pending_transaction_validation(context = %__MODULE__{}, valid?)
      when is_boolean(valid?) do
    %{context | valid_pending_transaction?: valid?}
  end

  @doc """
  Determine if the enough context has been retrieved

  ## Examples

      iex> %ValidationContext{
      ...>  cross_validation_nodes_confirmation: <<1::1, 0::1, 1::1>>,
      ...>  cross_validation_nodes: [
      ...>    %Node{first_public_key: "key1"},
      ...>    %Node{first_public_key: "key2"},
      ...>    %Node{first_public_key: "key3"}
      ...>  ]
      ...> }
      ...> |> ValidationContext.enough_confirmations?()
      false

      iex> %ValidationContext{
      ...>  cross_validation_nodes_confirmation: <<1::1, 1::1, 1::1>>,
      ...>  cross_validation_nodes: [
      ...>    %Node{first_public_key: "key1"},
      ...>    %Node{first_public_key: "key2"},
      ...>    %Node{first_public_key: "key3"}
      ...>  ]
      ...> }
      ...> |> ValidationContext.enough_confirmations?()
      true
  """
  @spec enough_confirmations?(t()) :: boolean()
  def enough_confirmations?(%__MODULE__{
        cross_validation_nodes: cross_validation_nodes,
        cross_validation_nodes_confirmation: confirmed_nodes
      }) do
    Enum.reduce(cross_validation_nodes, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end) ==
      confirmed_nodes
  end

  @doc """
  Confirm a cross validation node by setting a bit to 1 in the confirmation list

  ## Examples

      iex> %ValidationContext{
      ...>  cross_validation_nodes: [
      ...>    %Node{last_public_key: "key2"},
      ...>    %Node{last_public_key: "key3"}
      ...>  ],
      ...>  cross_validation_nodes_confirmation: <<0::1, 0::1>>
      ...> }
      ...> |> ValidationContext.confirm_validation_node("key3")
      %ValidationContext{
        cross_validation_nodes: [
          %Node{last_public_key: "key2"},
          %Node{last_public_key: "key3"}
        ],
        cross_validation_nodes_confirmation: <<0::1, 1::1>>
      }
  """
  def confirm_validation_node(
        context = %__MODULE__{cross_validation_nodes: cross_validation_nodes},
        node_public_key
      ) do
    index = Enum.find_index(cross_validation_nodes, &(&1.last_public_key == node_public_key))

    Map.update!(
      context,
      :cross_validation_nodes_confirmation,
      &Utils.set_bitstring_bit(&1, index)
    )
  end

  @doc """
  Add the validation stamp to the mining context
  """
  @spec add_validation_stamp(t(), ValidationStamp.t()) :: t()
  def add_validation_stamp(context = %__MODULE__{}, stamp = %ValidationStamp{}) do
    %{context | validation_stamp: stamp} |> add_io_storage_nodes()
  end

  @doc """
  Determines if the expected cross validation stamps have been received

  ## Examples

      iex> %ValidationContext{
      ...>  cross_validation_stamps: [
      ...>    %CrossValidationStamp{},
      ...>    %CrossValidationStamp{},
      ...>    %CrossValidationStamp{},
      ...>  ],
      ...>  cross_validation_nodes: [
      ...>    %Node{},
      ...>    %Node{},
      ...>    %Node{},
      ...>    %Node{},
      ...>  ]
      ...> }
      ...> |> ValidationContext.enough_cross_validation_stamps?()
      false
  """
  @spec enough_cross_validation_stamps?(t()) :: boolean()
  def enough_cross_validation_stamps?(%__MODULE__{
        cross_validation_nodes: cross_validation_nodes,
        cross_validation_stamps: stamps
      }) do
    length(cross_validation_nodes) == length(stamps)
  end

  @doc """
  Determines if the atomic commitment has been reached from the cross validation stamps.
  """
  @spec atomic_commitment?(t()) :: boolean()
  def atomic_commitment?(%__MODULE__{transaction: tx, cross_validation_stamps: stamps}) do
    %{tx | cross_validation_stamps: stamps}
    |> Transaction.atomic_commitment?()
  end

  @doc """
  Add a cross validation stamp if not exists
  """
  @spec add_cross_validation_stamp(t(), CrossValidationStamp.t()) :: t()
  def add_cross_validation_stamp(
        context = %__MODULE__{
          validation_stamp: validation_stamp
        },
        stamp = %CrossValidationStamp{
          node_public_key: from
        }
      ) do
    cond do
      !cross_validation_node?(context, from) ->
        context

      !CrossValidationStamp.valid_signature?(stamp, validation_stamp) ->
        context

      cross_validation_stamp_exists?(context, from) ->
        context

      true ->
        Map.update!(context, :cross_validation_stamps, &[stamp | &1])
    end
  end

  defp cross_validation_stamp_exists?(
         %__MODULE__{cross_validation_stamps: stamps},
         node_public_key
       )
       when is_binary(node_public_key) do
    Enum.any?(stamps, &(&1.node_public_key == node_public_key))
  end

  @doc """
  Determines if a node is a cross validation node

  ## Examples

      iex> %ValidationContext{
      ...>   coordinator_node: %Node{last_public_key: "key1"},
      ...>   cross_validation_nodes: [
      ...>     %Node{last_public_key: "key2"},
      ...>     %Node{last_public_key: "key3"},
      ...>     %Node{last_public_key: "key4"},
      ...>   ]
      ...> }
      ...> |> ValidationContext.cross_validation_node?("key3")
      true

      iex> %ValidationContext{
      ...>   coordinator_node: %Node{last_public_key: "key1"},
      ...>   cross_validation_nodes: [
      ...>     %Node{last_public_key: "key2"},
      ...>     %Node{last_public_key: "key3"},
      ...>     %Node{last_public_key: "key4"},
      ...>   ]
      ...> }
      ...> |> ValidationContext.cross_validation_node?("key1")
      false
  """
  @spec cross_validation_node?(t(), Crypto.key()) :: boolean()
  def cross_validation_node?(
        %__MODULE__{cross_validation_nodes: cross_validation_nodes},
        node_public_key
      )
      when is_binary(node_public_key) do
    Enum.any?(cross_validation_nodes, &(&1.last_public_key == node_public_key))
  end

  @doc """
  Add the replication tree and initialize the replication nodes confirmation list

  ## Examples

      iex> %ValidationContext{
      ...>    full_replication_tree: %{ chain: [<<0::1, 1::1>>, <<1::1, 0::1>>],  beacon: [<<0::1, 1::1>>, <<1::1, 0::1>>], IO: [<<0::1, 1::1>>, <<1::1, 0::1>>] },
      ...>    sub_replication_tree: %{ chain: <<1::1, 0::1>>, beacon: <<1::1, 0::1>>, IO: <<1::1, 0::1>> },
      ...>    replication_nodes_confirmation: %{ chain: <<0::1, 0::1>>, beacon: <<0::1, 0::1>>, IO: <<0::1, 0::1>> }
      ...> } = %ValidationContext{
      ...>    coordinator_node: %Node{last_public_key: "key1"},
      ...>    cross_validation_nodes: [%Node{last_public_key: "key2"}],
      ...> }
      ...> |> ValidationContext.add_replication_tree(%{ chain: [<<0::1, 1::1>>, <<1::1, 0::1>>], beacon: [<<0::1, 1::1>>, <<1::1, 0::1>>], IO: [<<0::1, 1::1>>, <<1::1, 0::1>>] }, "key2")
  """
  @spec add_replication_tree(
          t(),
          replication_trees :: %{
            chain: list(bitstring()),
            beacon: list(bitstring()),
            IO: list(bitstring())
          },
          node_public_key :: Crypto.key()
        ) :: t()
  def add_replication_tree(
        context = %__MODULE__{
          coordinator_node: coordinator_node,
          cross_validation_nodes: cross_validation_nodes
        },
        tree = %{chain: chain_tree, beacon: beacon_tree, IO: io_tree},
        node_public_key
      )
      when is_list(chain_tree) and is_list(beacon_tree) and is_list(io_tree) and
             is_binary(node_public_key) do
    validation_nodes = [coordinator_node | cross_validation_nodes]
    validator_index = Enum.find_index(validation_nodes, &(&1.last_public_key == node_public_key))

    sub_chain_tree = Enum.at(chain_tree, validator_index)

    sub_beacon_tree = Enum.at(beacon_tree, validator_index)
    sub_io_tree = Enum.at(io_tree, validator_index)

    sub_tree_size = bit_size(sub_chain_tree)

    %{
      context
      | sub_replication_tree: %{
          chain: sub_chain_tree,
          beacon: sub_beacon_tree,
          IO: sub_io_tree
        },
        full_replication_tree: tree,
        replication_nodes_confirmation: %{
          chain: <<0::size(sub_tree_size)>>,
          beacon: <<0::size(sub_tree_size)>>,
          IO: <<0::size(sub_tree_size)>>
        }
    }
  end

  @doc """
  Get the entire list of storage nodes (transaction chain, beacon chain, I/O)

  ## Examples

      iex> %ValidationContext{
      ...>   chain_storage_nodes: [%Node{first_public_key: "key1"}, %Node{first_public_key: "key2"}],
      ...>   beacon_storage_nodes: [%Node{first_public_key: "key3"}, %Node{first_public_key: "key1"}],
      ...>   io_storage_nodes: [%Node{first_public_key: "key4"}, %Node{first_public_key: "key5"}]
      ...> }
      ...> |> ValidationContext.get_storage_nodes()
      %{
        %Node{first_public_key: "key1"} => [:beacon, :chain],
        %Node{first_public_key: "key2"} => [:chain],
        %Node{first_public_key: "key3"} => [:beacon],
        %Node{first_public_key: "key4"} => [:IO],
        %Node{first_public_key: "key5"} => [:IO]
      }
  """
  @spec get_storage_nodes(t()) :: list(Node.t())
  def get_storage_nodes(%__MODULE__{
        chain_storage_nodes: chain_storage_nodes,
        beacon_storage_nodes: beacon_storage_nodes,
        io_storage_nodes: io_storage_nodes
      }) do
    [{:chain, chain_storage_nodes}, {:beacon, beacon_storage_nodes}, {:IO, io_storage_nodes}]
    |> Enum.reduce(%{}, fn {role, nodes}, acc ->
      Enum.reduce(nodes, acc, fn node, acc ->
        Map.update(acc, node, [role], &[role | &1])
      end)
    end)
  end

  @doc """
  Get the replication nodes from the replication trees for the actual subtree

  ## Examples

      iex> %ValidationContext{
      ...>   chain_storage_nodes: [
      ...>     %Node{last_public_key: "key5"},
      ...>     %Node{last_public_key: "key7"}
      ...>   ],
      ...>   beacon_storage_nodes: [
      ...>     %Node{last_public_key: "key10"},
      ...>     %Node{last_public_key: "key11"}
      ...>  ],
      ...>  io_storage_nodes: [
      ...>     %Node{last_public_key: "key12"},
      ...>     %Node{last_public_key: "key5"}
      ...>  ],
      ...>   sub_replication_tree: %{
      ...>     chain: <<1::1, 0::1>>,
      ...>     beacon: <<1::1, 0::1>>,
      ...>     IO: <<0::1, 1::1>>
      ...>   }
      ...> }
      ...> |> ValidationContext.get_replication_nodes()
      %{
        %Node{last_public_key: "key10"} => [:beacon],
        %Node{last_public_key: "key5"} => [:chain, :IO]
      }
  """
  @spec get_replication_nodes(t()) :: list(Node.t())
  def get_replication_nodes(%__MODULE__{
        sub_replication_tree: %{
          chain: chain_tree,
          beacon: beacon_tree,
          IO: io_tree
        },
        chain_storage_nodes: chain_storage_nodes,
        beacon_storage_nodes: beacon_storage_nodes,
        io_storage_nodes: io_storage_nodes
      }) do
    chain_storage_node_indexes = get_storage_nodes_tree_indexes(chain_tree)
    beacon_storage_node_indexes = get_storage_nodes_tree_indexes(beacon_tree)
    io_storage_node_indexes = get_storage_nodes_tree_indexes(io_tree)

    %{
      chain: Enum.map(chain_storage_node_indexes, &Enum.at(chain_storage_nodes, &1)),
      beacon: Enum.map(beacon_storage_node_indexes, &Enum.at(beacon_storage_nodes, &1)),
      IO: Enum.map(io_storage_node_indexes, &Enum.at(io_storage_nodes, &1))
    }
    |> Enum.reduce(%{}, fn {role, nodes}, acc ->
      Enum.reduce(nodes, acc, fn node, acc ->
        Map.update(acc, node, [role], &[role | &1])
      end)
    end)
  end

  defp get_storage_nodes_tree_indexes(tree) do
    tree
    |> Utils.bitstring_to_integer_list()
    |> Enum.with_index()
    |> Enum.filter(&match?({1, _}, &1))
    |> Enum.map(&elem(&1, 1))
  end

  @doc """
  Get the transaction validated including the validation stamp and cross validation stamps
  """
  @spec get_validated_transaction(t()) :: Transaction.t()
  def get_validated_transaction(%__MODULE__{
        transaction: transaction,
        validation_stamp: validation_stamp,
        cross_validation_stamps: cross_validation_stamps
      }) do
    %{
      transaction
      | validation_stamp: validation_stamp,
        cross_validation_stamps: cross_validation_stamps
    }
  end

  @doc """
  Acknowledge the replication confirm from the given storage node towards the given validator node

  ## Examples

      iex> %ValidationContext{replication_nodes_confirmation: %{
      ...>    chain: <<0::1, 0::1, 1::1>>,
      ...>    IO: <<0::1, 0::1, 0::1>>,
      ...>    beacon: <<0::1, 0::1, 0::1>>
      ...>  }} = %ValidationContext{
      ...>   replication_nodes_confirmation: %{ chain: <<0::1, 0::1, 0::1>>, beacon: <<0::1, 0::1, 0::1>>, IO: <<0::1, 0::1, 0::1>> },
      ...>   sub_replication_tree: %{ chain: <<0::1, 0::1, 0::1>>, IO: <<0::1, 0::1, 0::1>>, beacon: <<0::1, 0::1, 0::1>>},
      ...>   coordinator_node: %Node{last_public_key: "key1"},
      ...>   cross_validation_nodes: [%Node{last_public_key: "key2"}, %Node{last_public_key: "key3"}],
      ...>   chain_storage_nodes: [
      ...>     %Node{first_public_key: "key10", last_public_key: "key10"},
      ...>     %Node{first_public_key: "key11", last_public_key: "key11"},
      ...>     %Node{first_public_key: "key12", last_public_key: "key12"}
      ...>   ]
      ...> }
      ...> |> ValidationContext.confirm_replication("key12", [:chain])
  """
  @spec confirm_replication(
          t(),
          storage_node_key :: Crypto.key(),
          tree_types :: list(:chain | :beacon | :IO)
        ) :: t()
  def confirm_replication(
        context = %__MODULE__{
          chain_storage_nodes: chain_storage_nodes,
          beacon_storage_nodes: beacon_storage_nodes,
          io_storage_nodes: io_storage_nodes
        },
        from,
        tree_types
      ) do
    Enum.reduce(tree_types, context, fn
      :chain, acc ->
        index = Enum.find_index(chain_storage_nodes, &(&1.last_public_key == from))

        Map.update!(acc, :replication_nodes_confirmation, fn nodes ->
          Map.update!(nodes, :chain, &Utils.set_bitstring_bit(&1, index))
        end)

      :beacon, acc ->
        index = Enum.find_index(beacon_storage_nodes, &(&1.last_public_key == from))

        Map.update!(acc, :replication_nodes_confirmation, fn nodes ->
          Map.update!(nodes, :beacon, &Utils.set_bitstring_bit(&1, index))
        end)

      :IO, acc ->
        index = Enum.find_index(io_storage_nodes, &(&1.last_public_key == from))

        Map.update!(acc, :replication_nodes_confirmation, fn nodes ->
          Map.update!(nodes, :IO, &Utils.set_bitstring_bit(&1, index))
        end)
    end)
  end

  @doc """
  Determine if the number of replication nodes confirmation is reached

  ## Examples

      iex> %ValidationContext{
      ...>    replication_nodes_confirmation: %{
      ...>      chain: <<0::1, 1::1, 0::1>>,
      ...>      IO: <<0::1, 0::1, 0::1>>,
      ...>      beacon: <<0::1, 1::1, 0::1>>
      ...>    },
      ...>    sub_replication_tree: %{
      ...>      chain: <<0::1, 1::1, 0::1>>,
      ...>      IO: <<0::1, 1::1, 0::1>>,
      ...>      beacon: <<0::1, 1::1, 0::1>>
      ...>    }
      ...> }
      ...> |> ValidationContext.enough_replication_confirmations?()
      false

      iex> %ValidationContext{
      ...>    replication_nodes_confirmation: %{
      ...>      chain: <<0::1, 1::1, 0::1>>,
      ...>      IO: <<0::1, 1::1, 0::1>>,
      ...>      beacon: <<0::1, 1::1, 0::1>>
      ...>    },
      ...>    sub_replication_tree: %{
      ...>      chain: <<0::1, 1::1, 0::1>>,
      ...>      IO: <<0::1, 1::1, 0::1>>,
      ...>      beacon: <<0::1, 1::1, 0::1>>
      ...>    }
      ...> }
      ...> |> ValidationContext.enough_replication_confirmations?()
      true
  """
  @spec enough_replication_confirmations?(t()) :: boolean()
  def enough_replication_confirmations?(%__MODULE__{
        replication_nodes_confirmation: replication_nodes_confirmation,
        sub_replication_tree: replication_tree
      }) do
    Enum.all?(replication_nodes_confirmation, fn {tree, confirmations} ->
      Utils.count_bitstring_bits(confirmations) ==
        Utils.count_bitstring_bits(Map.get(replication_tree, tree))
    end)
  end

  @doc """
  Initialize the transaction mining context
  """
  @spec put_transaction_context(
          t(),
          Transaction.t(),
          list(UnspentOutput.t()),
          list(Node.t()),
          bitstring(),
          bitstring(),
          bitstring()
        ) :: t()
  def put_transaction_context(
        context = %__MODULE__{},
        previous_transaction,
        unspent_outputs,
        previous_storage_nodes,
        chain_storage_nodes_view,
        beacon_storage_nodes_view,
        validation_nodes_view
      ) do
    context
    |> Map.put(:previous_transaction, previous_transaction)
    |> Map.put(:unspent_outputs, unspent_outputs)
    |> Map.put(:previous_storage_nodes, previous_storage_nodes)
    |> Map.put(:chain_storage_nodes_view, chain_storage_nodes_view)
    |> Map.put(:beacon_storage_nodes_view, beacon_storage_nodes_view)
    |> Map.put(:validation_nodes_view, validation_nodes_view)
  end

  @doc """
  Aggregate the transaction mining context with the incoming context retrieved from the validation nodes

  ## Examples

      iex> %ValidationContext{
      ...>    previous_storage_nodes: [%Node{first_public_key: "key1"}],
      ...>    chain_storage_nodes_view: <<1::1, 1::1, 1::1>>,
      ...>    beacon_storage_nodes_view: <<1::1, 0::1, 1::1>>,
      ...>    validation_nodes_view: <<1::1, 1::1, 0::1>>,
      ...>    cross_validation_nodes: [%Node{last_public_key: "key3"}, %Node{last_public_key: "key5"}],
      ...>    cross_validation_nodes_confirmation: <<0::1, 0::1>>
      ...> }
      ...> |> ValidationContext.aggregate_mining_context(
      ...>    [%Node{first_public_key: "key2"}],
      ...>    <<1::1, 0::1, 1::1>>,
      ...>    <<1::1, 1::1, 1::1>>,
      ...>    <<1::1, 1::1, 1::1>>,
      ...>    "key5"
      ...> )
      %ValidationContext{
        previous_storage_nodes: [
          %Node{first_public_key: "key1"},
          %Node{first_public_key: "key2"}
        ],
        chain_storage_nodes_view: <<1::1, 1::1, 1::1>>,
        beacon_storage_nodes_view: <<1::1, 1::1, 1::1>>,
        validation_nodes_view: <<1::1, 1::1, 1::1>>,
        cross_validation_nodes_confirmation: <<0::1, 1::1>>,
        cross_validation_nodes: [%Node{last_public_key: "key3"}, %Node{last_public_key: "key5"}]
      }
  """
  @spec aggregate_mining_context(
          t(),
          list(Node.t()),
          bitstring(),
          bitstring(),
          bitstring(),
          Crypto.key()
        ) :: t()
  def aggregate_mining_context(
        context = %__MODULE__{},
        previous_storage_nodes,
        validation_nodes_view,
        chain_storage_nodes_view,
        beacon_storage_nodes_view,
        from
      )
      when is_list(previous_storage_nodes) and is_bitstring(validation_nodes_view) and
             is_bitstring(chain_storage_nodes_view) and
             is_bitstring(beacon_storage_nodes_view) do
    if cross_validation_node?(context, from) do
      context
      |> confirm_validation_node(from)
      |> aggregate_p2p_views(
        validation_nodes_view,
        chain_storage_nodes_view,
        beacon_storage_nodes_view
      )
      |> aggregate_previous_storage_nodes(previous_storage_nodes)
    else
      context
    end
  end

  defp aggregate_p2p_views(
         context = %__MODULE__{
           validation_nodes_view: validation_nodes_view1,
           chain_storage_nodes_view: chain_storage_nodes_view1,
           beacon_storage_nodes_view: beacon_storage_nodes_view1
         },
         validation_nodes_view2,
         chain_storage_nodes_view2,
         beacon_storage_nodes_view2
       )
       when is_bitstring(validation_nodes_view2) and is_bitstring(chain_storage_nodes_view2) and
              is_bitstring(beacon_storage_nodes_view2) do
    %{
      context
      | validation_nodes_view:
          Utils.aggregate_bitstring(validation_nodes_view1, validation_nodes_view2),
        chain_storage_nodes_view:
          Utils.aggregate_bitstring(chain_storage_nodes_view1, chain_storage_nodes_view2),
        beacon_storage_nodes_view:
          Utils.aggregate_bitstring(beacon_storage_nodes_view1, beacon_storage_nodes_view2)
    }
  end

  defp aggregate_previous_storage_nodes(
         context = %__MODULE__{previous_storage_nodes: previous_nodes},
         received_previous_storage_nodes
       )
       when is_list(received_previous_storage_nodes) do
    previous_storage_nodes = P2P.distinct_nodes([previous_nodes, received_previous_storage_nodes])
    %{context | previous_storage_nodes: previous_storage_nodes}
  end

  @doc """
  Return the validation nodes
  """
  @spec get_validation_nodes(t()) :: list(Node.t())
  def get_validation_nodes(%__MODULE__{
        coordinator_node: coordinator_node,
        cross_validation_nodes: cross_validation_nodes
      }) do
    [coordinator_node | cross_validation_nodes] |> P2P.distinct_nodes()
  end

  @doc """
  Create a validation stamp based on the validation context and add it to the context
  """
  @spec create_validation_stamp(t()) :: t()
  def create_validation_stamp(
        context = %__MODULE__{
          transaction: tx,
          previous_transaction: prev_tx,
          unspent_outputs: unspent_outputs,
          welcome_node: welcome_node,
          coordinator_node: coordinator_node,
          cross_validation_nodes: cross_validation_nodes,
          previous_storage_nodes: previous_storage_nodes,
          valid_pending_transaction?: valid_pending_transaction?
        }
      ) do
    initial_error = if valid_pending_transaction?, do: nil, else: :pending_transaction

    validation_stamp =
      %ValidationStamp{
        timestamp: DateTime.utc_now(),
        proof_of_work: do_proof_of_work(tx),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx, prev_tx]),
        proof_of_election:
          Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
        ledger_operations:
          %LedgerOperations{
            transaction_movements: resolve_transaction_movements(tx),
            fee: Transaction.fee(tx)
          }
          |> LedgerOperations.from_transaction(tx)
          |> LedgerOperations.distribute_rewards(
            welcome_node,
            coordinator_node,
            cross_validation_nodes,
            previous_storage_nodes
          )
          |> LedgerOperations.consume_inputs(tx.address, unspent_outputs),
        recipients: resolve_transaction_recipients(tx),
        errors: [initial_error, chain_error(prev_tx, tx)] |> Enum.filter(& &1)
      }
      |> ValidationStamp.sign()

    add_io_storage_nodes(%{context | validation_stamp: validation_stamp})
  end

  defp chain_error(nil, _tx = %Transaction{}), do: nil

  defp chain_error(
         prev_tx = %Transaction{data: %TransactionData{code: prev_code}},
         tx = %Transaction{}
       )
       when prev_code != "" do
    unless Contracts.accept_new_contract?(prev_tx, tx) do
      :contract_validation
    end
  end

  defp chain_error(_, _), do: nil

  defp resolve_transaction_movements(tx) do
    tx
    |> Transaction.get_movements()
    |> Task.async_stream(
      fn mvt = %TransactionMovement{to: to} ->
        %{mvt | to: TransactionChain.resolve_last_address(to, DateTime.utc_now())}
      end,
      on_timeout: :kill_task
    )
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Enum.into([], fn {:ok, res} -> res end)
  end

  defp resolve_transaction_recipients(%Transaction{
         data: %TransactionData{recipients: recipients}
       }) do
    recipients
    |> Task.async_stream(&TransactionChain.resolve_last_address(&1, DateTime.utc_now()),
      on_timeout: :kill_task
    )
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.into([], fn {:ok, res} -> res end)
  end

  defp add_io_storage_nodes(
         context = %__MODULE__{transaction: tx, validation_stamp: validation_stamp}
       ) do
    io_storage_nodes = Replication.io_storage_nodes(%{tx | validation_stamp: validation_stamp})
    %{context | io_storage_nodes: io_storage_nodes}
  end

  @doc """
  Create a replication tree based on the validation context (storage nodes and validation nodes)
  and store it as a bitstring list.

  ## Examples

      iex> %ValidationContext{
      ...>   coordinator_node: %Node{first_public_key: "key1", network_patch: "AAA", last_public_key: "key1"},
      ...>   cross_validation_nodes: [%Node{first_public_key: "key2", network_patch: "FAC",  last_public_key: "key2"}],
      ...>   chain_storage_nodes: [%Node{first_public_key: "key3", network_patch: "BBB"}, %Node{first_public_key: "key4", network_patch: "EFC"}]
      ...> }
      ...> |> ValidationContext.create_replication_tree()
      %ValidationContext{
        sub_replication_tree: %{
          chain: <<1::1, 0::1>>,
          beacon: <<>>,
          IO: <<>>
        },
        full_replication_tree: %{
          IO: [],
          beacon: [],
          chain: [<<1::1, 0::1>>, <<0::1, 1::1>>]
        },
        replication_nodes_confirmation: %{
          IO: <<0::1, 0::1>>,
          beacon: <<0::1, 0::1>>,
          chain: <<0::1, 0::1>>
        },
        coordinator_node: %Node{first_public_key: "key1", network_patch: "AAA", last_public_key: "key1"},
        cross_validation_nodes: [%Node{first_public_key: "key2", network_patch: "FAC", last_public_key: "key2"}],
        chain_storage_nodes: [%Node{first_public_key: "key3", network_patch: "BBB"}, %Node{first_public_key: "key4", network_patch: "EFC"}]
      }
  """
  @spec create_replication_tree(t()) :: t()
  def create_replication_tree(
        context = %__MODULE__{
          chain_storage_nodes: chain_storage_nodes,
          beacon_storage_nodes: beacon_storage_nodes,
          io_storage_nodes: io_storage_nodes
        }
      ) do
    validation_nodes = get_validation_nodes(context)
    chain_replication_tree = Replication.generate_tree(validation_nodes, chain_storage_nodes)
    beacon_replication_tree = Replication.generate_tree(validation_nodes, beacon_storage_nodes)
    io_replication_tree = Replication.generate_tree(validation_nodes, io_storage_nodes)

    tree = %{
      chain:
        Enum.map(chain_replication_tree, fn {_, list} ->
          P2P.bitstring_from_node_subsets(chain_storage_nodes, list)
        end),
      beacon:
        Enum.map(beacon_replication_tree, fn {_, list} ->
          P2P.bitstring_from_node_subsets(beacon_storage_nodes, list)
        end),
      IO:
        Enum.map(io_replication_tree, fn {_, list} ->
          P2P.bitstring_from_node_subsets(io_storage_nodes, list)
        end)
    }

    sub_tree = %{
      chain: tree |> Map.get(:chain) |> Enum.at(0, <<>>),
      beacon: tree |> Map.get(:beacon) |> Enum.at(0, <<>>),
      IO: tree |> Map.get(:IO) |> Enum.at(0, <<>>)
    }

    sub_tree_size = sub_tree |> Map.get(:chain) |> bit_size()

    %{
      context
      | sub_replication_tree: sub_tree,
        full_replication_tree: tree,
        replication_nodes_confirmation: %{
          chain: <<0::size(sub_tree_size)>>,
          beacon: <<0::size(sub_tree_size)>>,
          IO: <<0::size(sub_tree_size)>>
        }
    }
  end

  defp do_proof_of_work(tx) do
    result =
      tx
      |> ProofOfWork.list_origin_public_keys_candidates()
      |> ProofOfWork.find_transaction_origin_public_key(tx)

    case result do
      {:ok, pow} ->
        pow

      {:error, :not_found} ->
        ""
    end
  end

  @doc """
  Cross validate the validation stamp using the validation context as reference and
  listing the potential inconsistencies.

  The cross validation stamp is therefore signed and stored in the context
  """
  @spec cross_validate(t()) :: t()
  def cross_validate(context = %__MODULE__{validation_stamp: validation_stamp}) do
    inconsistencies = validation_stamp_inconsistencies(context)

    cross_stamp =
      %CrossValidationStamp{inconsistencies: inconsistencies}
      |> CrossValidationStamp.sign(validation_stamp)

    %{context | cross_validation_stamps: [cross_stamp]}
  end

  defp validation_stamp_inconsistencies(context = %__MODULE__{validation_stamp: stamp}) do
    subsets_verifications = [
      timestamp: fn -> valid_timestamp(stamp, context) end,
      signature: fn -> valid_stamp_signature(stamp, context) end,
      proof_of_work: fn -> valid_stamp_proof_of_work?(stamp, context) end,
      proof_of_integrity: fn -> valid_stamp_proof_of_integrity?(stamp, context) end,
      proof_of_election: fn -> valid_stamp_proof_of_election?(stamp, context) end,
      transaction_fee: fn -> valid_stamp_fee?(stamp, context) end,
      transaction_movements: fn -> valid_stamp_transaction_movements?(stamp, context) end,
      recipients: fn -> valid_stamp_recipients?(stamp, context) end,
      node_movements: fn -> valid_stamp_node_movements?(stamp, context) end,
      unspent_outputs: fn -> valid_stamp_unspent_outputs?(stamp, context) end,
      errors: fn -> valid_stamp_errors?(stamp, context) end
    ]

    subsets_verifications
    |> Enum.map(&{elem(&1, 0), elem(&1, 1).()})
    |> Enum.filter(&match?({_, false}, &1))
    |> Enum.map(&elem(&1, 0))
  end

  defp valid_timestamp(%ValidationStamp{timestamp: timestamp}, _) do
    diff = DateTime.diff(timestamp, DateTime.utc_now())
    diff <= 0 and diff > -10
  end

  defp valid_stamp_signature(stamp = %ValidationStamp{}, %__MODULE__{
         coordinator_node: %Node{last_public_key: coordinator_node_public_key}
       }) do
    ValidationStamp.valid_signature?(stamp, coordinator_node_public_key)
  end

  defp valid_stamp_proof_of_work?(%ValidationStamp{proof_of_work: pow}, %__MODULE__{
         transaction: tx
       }) do
    case pow do
      "" ->
        do_proof_of_work(tx) == ""

      _ ->
        Transaction.verify_origin_signature?(tx, pow)
    end
  end

  defp valid_stamp_proof_of_integrity?(%ValidationStamp{proof_of_integrity: poi}, %__MODULE__{
         transaction: tx,
         previous_transaction: prev_tx
       }),
       do: TransactionChain.proof_of_integrity([tx, prev_tx]) == poi

  defp valid_stamp_proof_of_election?(
         %ValidationStamp{proof_of_election: poe, timestamp: timestamp},
         %__MODULE__{
           transaction: tx
         }
       ),
       do: poe == Election.validation_nodes_election_seed_sorting(tx, timestamp)

  defp valid_stamp_fee?(
         %ValidationStamp{ledger_operations: %LedgerOperations{fee: fee}},
         %__MODULE__{transaction: tx}
       ),
       do: Transaction.fee(tx) == fee

  defp valid_stamp_errors?(%ValidationStamp{errors: errors}, %__MODULE__{
         transaction: tx,
         previous_transaction: prev_tx,
         valid_pending_transaction?: valid_pending_transaction?
       }) do
    initial_error = if valid_pending_transaction?, do: nil, else: :pending_transaction
    [initial_error, chain_error(prev_tx, tx)] |> Enum.filter(& &1) == errors
  end

  defp valid_stamp_recipients?(%ValidationStamp{recipients: recipients}, %__MODULE__{
         transaction: tx
       }),
       do: resolve_transaction_recipients(tx) == recipients

  defp valid_stamp_transaction_movements?(
         %ValidationStamp{ledger_operations: %LedgerOperations{transaction_movements: movements}},
         %__MODULE__{transaction: tx}
       ),
       do: resolve_transaction_movements(tx) == movements

  defp valid_stamp_unspent_outputs?(
         %ValidationStamp{
           ledger_operations: %LedgerOperations{unspent_outputs: next_unspent_outputs}
         },
         %__MODULE__{
           transaction: tx,
           unspent_outputs: previous_unspent_outputs
         }
       ) do
    %LedgerOperations{unspent_outputs: expected_unspent_outputs} =
      %LedgerOperations{
        fee: Transaction.fee(tx),
        transaction_movements: Transaction.get_movements(tx)
      }
      |> LedgerOperations.from_transaction(tx)
      |> LedgerOperations.consume_inputs(tx.address, previous_unspent_outputs)

    expected_unspent_outputs == next_unspent_outputs
  end

  defp valid_stamp_node_movements?(%ValidationStamp{ledger_operations: ops}, %__MODULE__{
         transaction: tx,
         welcome_node: %Node{last_public_key: welcome_node_public_key},
         coordinator_node: %Node{last_public_key: coordinator_node_public_key},
         cross_validation_nodes: cross_validation_nodes,
         unspent_outputs: unspent_outputs
       }) do
    previous_storage_nodes =
      P2P.distinct_nodes([unspent_storage_nodes(unspent_outputs), previous_storage_nodes(tx)])

    with true <- LedgerOperations.valid_node_movements_roles?(ops),
         true <-
           LedgerOperations.valid_node_movements_cross_validation_nodes?(
             ops,
             Enum.map(cross_validation_nodes, & &1.last_public_key)
           ),
         true <-
           LedgerOperations.valid_node_movements_previous_storage_nodes?(
             ops,
             Enum.map(previous_storage_nodes, & &1.last_public_key)
           ),
         true <- LedgerOperations.valid_reward_distribution?(ops),
         true <-
           LedgerOperations.has_node_movement_with_role?(
             ops,
             welcome_node_public_key,
             :welcome_node
           ),
         true <-
           LedgerOperations.has_node_movement_with_role?(
             ops,
             coordinator_node_public_key,
             :coordinator_node
           ),
         true <-
           Enum.all?(
             cross_validation_nodes,
             &LedgerOperations.has_node_movement_with_role?(
               ops,
               &1.last_public_key,
               :cross_validation_node
             )
           ) do
      true
    end
  end

  defp unspent_storage_nodes([]), do: []

  defp unspent_storage_nodes(unspent_outputs) do
    unspent_outputs
    |> Stream.map(&Replication.chain_storage_nodes(&1.from))
    |> Enum.to_list()
  end

  defp previous_storage_nodes(tx) do
    tx
    |> Transaction.previous_address()
    |> Replication.chain_storage_nodes()
  end
end
