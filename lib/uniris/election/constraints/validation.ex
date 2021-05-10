defmodule Uniris.Election.ValidationConstraints do
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

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.UCOLedger

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
          data: %TransactionData{ledger: %Ledger{uco: %UCOLedger{transfers: transfers}}}
        },
        nb_authorized_nodes
      )
      when is_integer(nb_authorized_nodes) do
    total_transfers = Enum.reduce(transfers, 0.0, &(&2 + &1.amount))

    if total_transfers > 10 do
      validation_number =
        trunc(
          :math.floor(min_validation_nodes(nb_authorized_nodes) * :math.log10(total_transfers))
        )

      if validation_number > nb_authorized_nodes do
        nb_authorized_nodes
      else
        validation_number
      end
    else
      min_validation_nodes(nb_authorized_nodes)
    end
  end
end
