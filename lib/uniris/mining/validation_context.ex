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
    sub_replication_tree: <<>>,
    full_replication_tree: [],
    io_storage_nodes: [],
    previous_storage_nodes: [],
    replication_nodes_confirmation: <<>>
  ]

  alias Uniris.Contracts

  alias Uniris.Crypto

  alias Uniris.Mining.ProofOfWork

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.OracleChain

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
          full_replication_tree: list(bitstring()),
          sub_replication_tree: bitstring(),
          cross_validation_stamps: list(CrossValidationStamp.t()),
          replication_nodes_confirmation: bitstring(),
          validation_nodes_view: bitstring(),
          chain_storage_nodes_view: bitstring(),
          beacon_storage_nodes_view: bitstring()
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

      iex> %ValidationContext{cross_validation_nodes_confirmation: <<0::1, 1::1>>} = %ValidationContext{
      ...>  cross_validation_nodes: [
      ...>    %Node{last_public_key: "key2"},
      ...>    %Node{last_public_key: "key3"}
      ...>  ],
      ...>  cross_validation_nodes_confirmation: <<0::1, 0::1>>
      ...> }
      ...> |> ValidationContext.confirm_validation_node("key3")
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
      ...>    full_replication_tree: [<<0::1, 1::1>>, <<1::1, 0::1>>],
      ...>    sub_replication_tree: <<1::1, 0::1>>,
      ...>    replication_nodes_confirmation: <<0::1, 0::1>>
      ...> } = %ValidationContext{
      ...>    coordinator_node: %Node{last_public_key: "key1"},
      ...>    cross_validation_nodes: [%Node{last_public_key: "key2"}],
      ...> }
      ...> |> ValidationContext.add_replication_tree([<<0::1, 1::1>>, <<1::1, 0::1>>], "key2")
  """
  @spec add_replication_tree(
          t(),
          replication_trees :: list(bitstring()),
          node_public_key :: Crypto.key()
        ) :: t()
  def add_replication_tree(
        context = %__MODULE__{
          coordinator_node: coordinator_node,
          cross_validation_nodes: cross_validation_nodes
        },
        tree,
        node_public_key
      )
      when is_list(tree) and is_binary(node_public_key) do
    validation_nodes = [coordinator_node | cross_validation_nodes]
    validator_index = Enum.find_index(validation_nodes, &(&1.last_public_key == node_public_key))
    sub_tree = Enum.at(tree, validator_index)
    sub_tree_size = bit_size(sub_tree)

    %{
      context
      | sub_replication_tree: sub_tree,
        full_replication_tree: tree,
        replication_nodes_confirmation: <<0::size(sub_tree_size)>>
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
      [
        %Node{first_public_key: "key1"},
        %Node{first_public_key: "key2"},
        %Node{first_public_key: "key3"},
        %Node{first_public_key: "key4"},
        %Node{first_public_key: "key5"}
      ]
  """
  @spec get_storage_nodes(t()) :: list(Node.t())
  def get_storage_nodes(%__MODULE__{
        chain_storage_nodes: chain_storage_nodes,
        beacon_storage_nodes: beacon_storage_nodes,
        io_storage_nodes: io_storage_nodes
      }) do
    [chain_storage_nodes, beacon_storage_nodes, io_storage_nodes]
    |> P2P.distinct_nodes()
  end

  @doc """
  Get the replication nodes from the replication tree for the given validation node public key

  ## Examples

      iex> [
      ...>    %Node{last_public_key: "key5"},
      ...>    %Node{last_public_key: "key11"}
      ...>  ] = %ValidationContext{
      ...>   chain_storage_nodes: [
      ...>     %Node{first_public_key: "key5", last_public_key: "key5"},
      ...>     %Node{first_public_key: "key7", last_public_key: "key7"}
      ...>   ],
      ...>   beacon_storage_nodes: [
      ...>     %Node{first_public_key: "key10", last_public_key: "key10"},
      ...>     %Node{first_public_key: "key11", last_public_key: "key11"}
      ...>  ],
      ...>   sub_replication_tree: <<1::1, 0::1, 0::1, 1::1>>
      ...> }
      ...> |> ValidationContext.get_replication_nodes()
  """
  @spec get_replication_nodes(t()) :: list(Node.t())
  def get_replication_nodes(context = %__MODULE__{sub_replication_tree: tree}) do
    do_get_replication_nodes(tree, get_storage_nodes(context))
  end

  defp do_get_replication_nodes(bit_tree, storage_nodes, index \\ 0, acc \\ [])

  defp do_get_replication_nodes(<<1::1, rest::bitstring>>, storage_nodes, index, acc) do
    do_get_replication_nodes(rest, storage_nodes, index + 1, [Enum.at(storage_nodes, index) | acc])
  end

  defp do_get_replication_nodes(<<0::1, rest::bitstring>>, storage_nodes, index, acc) do
    do_get_replication_nodes(rest, storage_nodes, index + 1, acc)
  end

  defp do_get_replication_nodes(<<>>, _storage_nodes, _index, acc) do
    Enum.reverse(acc)
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

      iex> %ValidationContext{replication_nodes_confirmation: <<0::1, 0::1, 1::1>>} = %ValidationContext{
      ...>   replication_nodes_confirmation: <<0::1, 0::1, 0::1>>,
      ...>   sub_replication_tree: <<0::1, 0::1, 0::1>>,
      ...>   coordinator_node: %Node{last_public_key: "key1"},
      ...>   cross_validation_nodes: [%Node{last_public_key: "key2"}, %Node{last_public_key: "key3"}],
      ...>   chain_storage_nodes: [
      ...>     %Node{first_public_key: "key10", last_public_key: "key10"},
      ...>     %Node{first_public_key: "key11", last_public_key: "key11"},
      ...>     %Node{first_public_key: "key12", last_public_key: "key12"}
      ...>   ]
      ...> }
      ...> |> ValidationContext.confirm_replication("key12")
  """
  @spec confirm_replication(t(), storage_node_key :: Crypto.key()) :: t()
  def confirm_replication(context = %__MODULE__{}, from) do
    index =
      context
      |> get_storage_nodes()
      |> Enum.find_index(&(&1.last_public_key == from))

    Map.update!(context, :replication_nodes_confirmation, &Utils.set_bitstring_bit(&1, index))
  end

  @doc """
  Determine if the number of replication nodes confirmation is reached

  ## Examples

      iex> %ValidationContext{
      ...>    replication_nodes_confirmation: <<0::1, 1::1, 0::1, 0::1, 0::1>>,
      ...>    sub_replication_tree: <<0::1, 1::1, 0::1, 1::1, 1::1>>
      ...> }
      ...> |> ValidationContext.enough_replication_confirmations?()
      false

      iex> %ValidationContext{
      ...>    replication_nodes_confirmation: <<0::1, 1::1, 0::1, 1::1, 1::1>>,
      ...>    sub_replication_tree: <<0::1, 1::1, 0::1, 1::1, 1::1>>
      ...> }
      ...> |> ValidationContext.enough_replication_confirmations?()
      true
  """
  @spec enough_replication_confirmations?(t()) :: boolean()
  def enough_replication_confirmations?(%__MODULE__{
        replication_nodes_confirmation: replication_nodes_confirmation,
        sub_replication_tree: replication_tree
      }) do
    Utils.count_bitstring_bits(replication_nodes_confirmation) ==
      Utils.count_bitstring_bits(replication_tree)
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
          previous_storage_nodes: previous_storage_nodes
        }
      ) do
    validation_stamp =
      %ValidationStamp{
        proof_of_work: do_proof_of_work(tx),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx, prev_tx]),
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
        errors: errors_detection(prev_tx, tx)
      }
      |> ValidationStamp.sign()

    add_io_storage_nodes(%{context | validation_stamp: validation_stamp})
  end

  defp errors_detection(nil, tx = %Transaction{}) do
    [error_type_detection(tx)]
    |> Enum.reject(&match?({_, true}, &1))
    |> Enum.map(fn {domain, _} -> domain end)
  end

  defp errors_detection(prev_tx = %Transaction{}, tx = %Transaction{}) do
    [
      {:contract_validation, Contracts.accept_new_contract?(prev_tx, tx)},
      error_type_detection(tx)
    ]
    |> Enum.reject(&match?({_, true}, &1))
    |> Enum.map(fn {domain, _} -> domain end)
  end

  defp error_type_detection(tx = %Transaction{type: :oracle}) do
    {:oracle_validation, OracleChain.verify?(tx)}
  end

  defp error_type_detection(tx = %Transaction{type: :oracle_summary}) do
    {:oracle_validation, OracleChain.verify?(tx)}
  end

  defp error_type_detection(%Transaction{type: type}), do: {type, true}

  defp resolve_transaction_movements(tx) do
    tx
    |> Transaction.get_movements()
    |> Task.async_stream(fn mvt = %TransactionMovement{to: to} ->
      %{mvt | to: TransactionChain.resolve_last_address(to)}
    end)
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Enum.into([], fn {:ok, res} -> res end)
  end

  defp resolve_transaction_recipients(%Transaction{data: %TransactionData{recipients: recipients}}) do
    recipients
    |> Task.async_stream(&TransactionChain.resolve_last_address/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.into([], fn {:ok, res} -> res end)
  end

  defp add_io_storage_nodes(
         context = %__MODULE__{validation_stamp: %ValidationStamp{ledger_operations: ops}}
       ) do
    io_storage_nodes = Replication.io_storage_nodes(ops)
    %{context | io_storage_nodes: io_storage_nodes}
  end

  @doc """
  Create a replication tree based on the validation context (storage nodes and validation nodes)
  and store it as a bitstring list.<

  ## Examples

      iex> %ValidationContext{
      ...>   coordinator_node: %Node{first_public_key: "key1", network_patch: "AAA", last_public_key: "key1"},
      ...>   cross_validation_nodes: [%Node{first_public_key: "key2", network_patch: "FAC",  last_public_key: "key2"}],
      ...>   chain_storage_nodes: [%Node{first_public_key: "key3", network_patch: "BBB"}, %Node{first_public_key: "key4", network_patch: "EFC"}]
      ...> }
      ...> |> ValidationContext.create_replication_tree()
      %ValidationContext{
        sub_replication_tree: <<1::1, 0::1>>,
        full_replication_tree: [<<1::1, 0::1>>, <<0::1, 1::1>>],
        replication_nodes_confirmation: <<0::1, 0::1>>,
        coordinator_node: %Node{first_public_key: "key1", network_patch: "AAA", last_public_key: "key1"},
        cross_validation_nodes: [%Node{first_public_key: "key2", network_patch: "FAC", last_public_key: "key2"}],
        chain_storage_nodes: [%Node{first_public_key: "key3", network_patch: "BBB"}, %Node{first_public_key: "key4", network_patch: "EFC"}]
      }
  """
  @spec create_replication_tree(t()) :: t()
  def create_replication_tree(context = %__MODULE__{}) do
    storage_nodes = get_storage_nodes(context)

    tree =
      context
      |> get_validation_nodes
      |> Replication.generate_tree(storage_nodes)
      |> Enum.map(fn {_, list} -> P2P.bitstring_from_node_subsets(storage_nodes, list) end)

    sub_tree = Enum.at(tree, 0)
    sub_tree_size = bit_size(sub_tree)

    %{
      context
      | sub_replication_tree: sub_tree,
        full_replication_tree: tree,
        replication_nodes_confirmation: <<0::size(sub_tree_size)>>
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

  defp validation_stamp_inconsistencies(
         context = %__MODULE__{
           transaction: tx,
           previous_transaction: prev_tx,
           unspent_outputs: previous_unspent_outputs,
           coordinator_node: %Node{last_public_key: coordinator_node_public_key},
           validation_stamp:
             stamp = %ValidationStamp{
               proof_of_work: pow,
               proof_of_integrity: poi,
               ledger_operations:
                 operations = %LedgerOperations{
                   fee: fee,
                   transaction_movements: tx_movements,
                   unspent_outputs: next_unspent_outputs
                 },
               recipients: tx_recipients,
               errors: errors
             }
         }
       ) do
    resolved_transaction_movements = resolve_transaction_movements(tx)

    subsets_verifications = [
      signature: fn -> ValidationStamp.valid_signature?(stamp, coordinator_node_public_key) end,
      proof_of_work: fn -> valid_proof_of_work?(pow, tx) end,
      proof_of_integrity: fn -> TransactionChain.proof_of_integrity([tx, prev_tx]) == poi end,
      transaction_fee: fn -> Transaction.fee(tx) == fee end,
      transaction_movements: fn -> resolved_transaction_movements == tx_movements end,
      recipients: fn -> resolve_transaction_recipients(tx) == tx_recipients end,
      node_movements: fn -> valid_node_movements?(operations, context) end,
      unspent_outputs: fn ->
        valid_unspent_outputs?(
          tx,
          previous_unspent_outputs,
          next_unspent_outputs,
          resolved_transaction_movements
        )
      end,
      errors: fn ->
        errors_detection(prev_tx, tx) == errors
      end
    ]

    subsets_verifications
    |> Enum.map(&{elem(&1, 0), elem(&1, 1).()})
    |> Enum.filter(&match?({_, false}, &1))
    |> Enum.map(&elem(&1, 0))
  end

  defp valid_proof_of_work?(pow, tx) do
    case pow do
      "" ->
        do_proof_of_work(tx) == ""

      _ ->
        Transaction.verify_origin_signature?(tx, pow)
    end
  end

  defp valid_unspent_outputs?(
         tx,
         previous_unspent_outputs,
         next_unspent_outputs,
         resolved_transaction_movements
       ) do
    %LedgerOperations{unspent_outputs: expected_unspent_outputs} =
      %LedgerOperations{
        fee: Transaction.fee(tx),
        transaction_movements: resolved_transaction_movements
      }
      |> LedgerOperations.from_transaction(tx)
      |> LedgerOperations.consume_inputs(tx.address, previous_unspent_outputs)

    expected_unspent_outputs == next_unspent_outputs
  end

  defp valid_node_movements?(ops = %LedgerOperations{}, %__MODULE__{
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
    node_list = P2P.list_nodes(availability: :global)

    unspent_outputs
    |> Stream.map(&Replication.chain_storage_nodes(&1.from, node_list))
    |> Enum.to_list()
  end

  defp previous_storage_nodes(tx) do
    tx
    |> Transaction.previous_address()
    |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
  end
end
