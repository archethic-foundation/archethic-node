defmodule UnirisCore.Election.Constraints do
  @moduledoc """
  Election algorithms are based on constrains with heuristics aims to the best case.

  However this function can overrided in the election function to provide the most accurate
  tuning through the network evolution and monitor for example via the Prediction module.
  """

  use GenServer

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.Election.ValidationConstraints
  alias UnirisCore.Election.StorageConstraints

  @default_min_validations 3

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok,
     %{
       validation: %ValidationConstraints{
         min_geo_patch: &min_validation_geo_patch/0,
         min_validation_number: @default_min_validations,
         validation_number: &validation_number/1
       },
       storage: %StorageConstraints{
         min_geo_patch: &min_storage_geo_patch/0,
         min_geo_patch_avg_availability: &min_storage_geo_patch_avg_availability/0,
         number_replicas: &number_replicas/1
       }
     }}
  end

  def handle_call(:validation_constraints, _from, state = %{validation: validation_constraints}) do
    {:reply, validation_constraints, state}
  end

  def handle_call(:storage_constraints, _from, state = %{storage: storage_constraints}) do
    {:reply, storage_constraints, state}
  end

  @spec for_validation() :: ValidationConstraints.t()
  def for_validation() do
    GenServer.call(__MODULE__, :validation_constraints)
  end

  @spec for_storage() :: StorageConstraints.t()
  def for_storage() do
    GenServer.call(__MODULE__, :storage_constraints)
  end

  @doc """
  Require number of distinct geographic patch for the elected validation nodes.

  This property ensure the geographical security of the transaction validation by spliting
  the computation in many place on the world.
  """
  @spec min_validation_geo_patch() :: non_neg_integer()
  def min_validation_geo_patch, do: 3

  @doc """
  Require number of distinc geograpihc patch for the elected storage nodes.

  This property ensure the geographical security of the sharding by spliting in
  many place on the world.
  It aims to support disaster recovery
  """
  @spec min_storage_geo_patch() :: non_neg_integer()
  def min_storage_geo_patch, do: 4

  @doc """
  Require number of average availability by distinct geographical patches.

  This property ensures than each patch of the sharding will support a certain availability
  from these nodes.
  """
  @spec min_storage_geo_patch_avg_availability() :: float()
  def min_storage_geo_patch_avg_availability, do: 0.8

  @doc """
  Require number of validation nodes for a given transaction.

  By default 5 validations is required, but if the amount of UCO to transfer
  a logarithmic progression is done to increase the number of validations
  """
  @spec validation_number(Transaction.pending()) :: non_neg_integer()
  def validation_number(%Transaction{data: %TransactionData{ledger: %Ledger{uco: %UCOLedger{transfers: transfers}}}})
      when length(transfers) > 0 do
    total_transfers = Enum.map(transfers, & &1.amount) |> Enum.sum()

    min_validations = @default_min_validations

    if total_transfers > 10 do
      :math.floor(min_validations * :math.log10(total_transfers)) |> trunc
    else
      min_validations
    end
  end

  def validation_number(%Transaction{}), do: @default_min_validations

  @doc """
  Require number of storages nodes for a given list of nodes according to their
  availability.

  To support data availability, cumulative average availability
  should be greater than `2^(log10(n)+5)`.

  From 143 nodes the number replicas start to reduce from the number of nodes.
  Just to ensure some stability in the network the sharding can evolve and later on the
  `HypergeometricDistribution` could be used instead to reduce to ~~200 nodes.
  """
  @spec number_replicas(nonempty_list(Node.t()), (non_neg_integer -> non_neg_integer)) ::
          non_neg_integer()
  def number_replicas(
        nodes,
        formula_threshold_cumul_availability \\ fn nb_nodes ->
          Float.round(:math.pow(2, :math.log10(nb_nodes) + 5))
        end
      )
      when is_list(nodes) and length(nodes) >= 1 do
    nb_nodes = length(nodes)
    threshold_cumul_availability = formula_threshold_cumul_availability.(nb_nodes)

    Enum.reduce_while(nodes, %{cumul_average_availability: 0, nb: 0}, fn node, acc ->
      if acc.cumul_average_availability >= threshold_cumul_availability do
        {:halt, acc}
      else
        {
          :cont,
          acc
          |> Map.update!(:nb, &(&1 + 1))
          |> Map.update!(:cumul_average_availability, &(&1 + node.average_availability))
        }
      end
    end)
    |> Map.get(:nb)
  end
end
