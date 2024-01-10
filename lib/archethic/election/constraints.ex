defmodule Archethic.Election.Constraints do
  @moduledoc """
  Election algorithms are based on constrains with heuristics aims to the best case.

  However those functions can override the election constraints to provide the most accurate
  tuning through the network evolution and monitor for example via the Prediction module.
  """

  use GenServer
  @vsn 1

  alias Archethic.Election.StorageConstraints
  alias Archethic.Election.ValidationConstraints

  @table_name :archethic_election_constraints

  @doc """
  Initialize the constraints ETS tables with default validation and storage constraints
  """
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    :ets.insert(@table_name, {:validation, ValidationConstraints.new()})
    :ets.insert(@table_name, {:storage, StorageConstraints.new()})

    {:ok, []}
  end

  @doc """
  Get the latest validation constraints
  """
  @spec get_validation_constraints() :: ValidationConstraints.t()
  def get_validation_constraints do
    [{_, validation_constraints}] = :ets.lookup(@table_name, :validation)
    validation_constraints
  end

  @doc """
  Set new validation constraints
  """
  @spec set_validation_constraints(ValidationConstraints.t()) :: :ok
  def set_validation_constraints(constraints = %ValidationConstraints{}) do
    true = :ets.insert(@table_name, {:validation, constraints})
    :ok
  end

  @doc """
  Get the latest storage constraints
  """
  @spec get_storage_constraints() :: StorageConstraints.t()
  def get_storage_constraints do
    [{_, storage_constraints}] = :ets.lookup(@table_name, :storage)
    storage_constraints
  end

  @doc """
  Set new storage constraints
  """
  @spec set_storage_constraints(StorageConstraints.t()) :: :ok
  def set_storage_constraints(constraints = %StorageConstraints{}) do
    true = :ets.insert(@table_name, {:storage, constraints})
    :ok
  end
end
