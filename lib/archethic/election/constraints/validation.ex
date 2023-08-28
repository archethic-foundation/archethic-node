defmodule Archethic.Election.ValidationConstraints do
  @moduledoc """
  Represents the constraints for the validation nodes election
  """

  @default_min_validation_geo_patch 3
  @default_min_validations 3

  defstruct [
    :min_geo_patch,
    :min_validation_nodes,
    :validation_number
  ]

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  alias Archethic.Utils

  @typedoc """
  Each validation constraints represent a function which will be executed during the election algorithms:
  - min_geo_patch: Require number of distinct geographic patch for the elected validation nodes.
  This property ensure the geographical security of the transaction validation by spliting
  the computation in many place on the world.
  - min_validation_nodes: Require number of minimum validation nodes.
  - validation_number: Require number of validation nodes for a given transaction.
  """
  @type t :: %__MODULE__{
          min_geo_patch: (() -> non_neg_integer()),
          min_validation_nodes: (non_neg_integer() -> non_neg_integer()),
          validation_number: (Transaction.t(), non_neg_integer() -> non_neg_integer())
        }

  def new(
        min_geo_patch_fun \\ &min_geo_patch/0,
        min_validation_nodes_fun \\ &min_validation_nodes/1,
        validation_number_fun \\ &validation_number/2
      ) do
    %__MODULE__{
      min_geo_patch: min_geo_patch_fun,
      min_validation_nodes: min_validation_nodes_fun,
      validation_number: validation_number_fun
    }
  end

  @doc """
  Determine the minimum of geo patch to cover
  """
  @spec min_geo_patch :: non_neg_integer()
  def min_geo_patch, do: @default_min_validation_geo_patch

  @doc """
  Define the minimum of validations
  """
  @spec min_validation_nodes(non_neg_integer()) :: non_neg_integer()
  def min_validation_nodes(nb_authorized_nodes)
      when nb_authorized_nodes < @default_min_validations,
      do: nb_authorized_nodes

  def min_validation_nodes(_), do: @default_min_validations

  @doc """
  Get the number of validations for a given transaction.
  """
  @spec validation_number(Transaction.t(), nb_authorized_nodes :: non_neg_integer()) ::
          non_neg_integer()
  def validation_number(
        %Transaction{
          data: %TransactionData{ledger: %Ledger{uco: uco_ledger}}
        },
        nb_authorized_nodes
      )
      when is_integer(nb_authorized_nodes) do
    min_nb_nodes = min_validation_nodes(nb_authorized_nodes)
    default_nb_nodes = overbook_validation_nodes(min_nb_nodes)

    total_transfers = UCOLedger.total_amount(uco_ledger)

    if total_transfers > 0 do
      additional_validations =
        total_transfers
        |> Utils.from_bigint()
        |> :math.log10()
        |> trunc()

      validation_number = default_nb_nodes + additional_validations

      cond do
        validation_number > nb_authorized_nodes ->
          nb_authorized_nodes

        validation_number < default_nb_nodes ->
          default_nb_nodes

        true ->
          validation_number
      end
    else
      default_nb_nodes
    end
  end

  defp overbook_validation_nodes(min_validation_nodes) do
    ceil(min_validation_nodes * 1.5)
  end
end
