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
          min_geo_patch: non_neg_integer | (() -> non_neg_integer()),
          min_validation_nodes: non_neg_integer | (() -> non_neg_integer()),
          validation_number: non_neg_integer | (Transaction.t() -> non_neg_integer())
        }

  def new(
        min_geo_patch_fun \\ &min_geo_patch/0,
        min_validation_nodes_fun \\ &min_validation_nodes/0,
        validation_number_fun \\ &validation_number/1
      ) do
    %__MODULE__{
      min_geo_patch: min_geo_patch_fun,
      min_validation_nodes: min_validation_nodes_fun,
      validation_number: validation_number_fun
    }
  end

  def min_geo_patch, do: @default_min_validation_geo_patch

  def min_validation_nodes, do: @default_min_validations

  @doc """
  Get the number of validations for a given transaction.

  ## Examples

      iex> ValidationConstraints.validation_number(%Transaction{
      ...>   data: %TransactionData{
      ...>    ledger: %Ledger{
      ...>       uco: %UCOLedger{
      ...>         transfers: [ %Transfer{to: "@Alice2", amount: 0.05 } ]
      ...>       }
      ...>    }
      ...> }})
      3

      iex> ValidationConstraints.validation_number(%Transaction{
      ...>   data: %TransactionData{
      ...>    ledger: %Ledger{
      ...>       uco: %UCOLedger{
      ...>         transfers: [ %Transfer{to: "@Alice2", amount: 200 } ]
      ...>       }
      ...>    }
      ...> }})
      6
  """
  def validation_number(%Transaction{
        data: %TransactionData{ledger: %Ledger{uco: %UCOLedger{transfers: transfers}}}
      })
      when length(transfers) > 0 do
    total_transfers = Enum.reduce(transfers, 0, &(&2 + &1.amount))

    min_validations = @default_min_validations

    if total_transfers > 10 do
      :math.floor(min_validations * :math.log10(total_transfers)) |> trunc
    else
      min_validations
    end
  end

  def validation_number(%Transaction{}), do: @default_min_validations
end
