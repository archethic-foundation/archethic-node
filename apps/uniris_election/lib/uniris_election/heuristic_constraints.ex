defmodule UnirisElection.HeuristicConstraints do
  @moduledoc """
  Election algorithms are based on constrains with heuristics aims to the best case.

  However this function can overrided in the election function to provide the most accurate
  tuning through the network evolution and monitor for example via the Prediction module.
  """

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.Data.Ledger.UCO, as: UCOLedger

  @min_validations 5

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
  Require number of average availability by distinc geographical patches.

  This property ensures than each patch of the sharding will support a certain availability
  from these nodes.
  """
  @spec min_storage_geo_patch_avg_availability() :: non_neg_integer()
  def min_storage_geo_patch_avg_availability, do: 8

  @doc """
  Require number of validation nodes for a given transaction.

  By default 5 validations is required, but if the amount of UCO to transfer
  a logarithmic progression is done to increase the number of validations

  ## Examples

      iex> tx = %UnirisChain.Transaction{
      ...>  address: "0489F19A241A5BA435CBD533EFA4D446696873030DA0B55BC64C6EF0184AA2F6",
      ...>  timestamp: 1573054121,
      ...>  type: :ledger,
      ...>  data: %UnirisChain.Transaction.Data{
      ...>    ledger: %UnirisChain.Transaction.Data.Ledger{
      ...>      uco: %UnirisChain.Transaction.Data.Ledger.UCO{
      ...>         transfers: [
      ...>             %UnirisChain.Transaction.Data.Ledger.Transfer{
      ...>               to: "2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824",
      ...>               amount: 2
      ...>             }
      ...>         ]
      ...>      }
      ...>    }
      ...>  },
      ...>  previous_public_key: "00EE9EBD56635EFA6C6382747CEC9B4B7E52B3E3CFF8B7A16077AC47E48EC06D38",
      ...>  previous_signature: "4DB9FF771458F8DBCB8CC18101DFF133E60BF99B0A09C25275422B0787BA6597C567F7F27D21D55FE1B211798F17543A7466D27F2F11CD64D802E526AAC19E06",
      ...>  origin_signature: "DA9252B7B0975B4208C80008817D9CE3F8BC7E3785D3CF3175D4BA248A55220F838F19742285A5F397F3350A8BFF779FB3F58AC078D4904557C973CEAE490904"
      ...> }
      iex> UnirisElection.HeuristicConstraints.validation_number(tx)
      5

      iex> tx = %UnirisChain.Transaction{
      ...>  address: "0489F19A241A5BA435CBD533EFA4D446696873030DA0B55BC64C6EF0184AA2F6",
      ...>  timestamp: 1573054121,
      ...>  type: :ledger,
      ...>  data: %UnirisChain.Transaction.Data{
      ...>    ledger: %UnirisChain.Transaction.Data.Ledger{
      ...>      uco: %UnirisChain.Transaction.Data.Ledger.UCO{
      ...>         transfers: [
      ...>           %UnirisChain.Transaction.Data.Ledger.Transfer{
      ...>             to: "2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824",
      ...>             amount: 10
      ...>           },
      ...>           %UnirisChain.Transaction.Data.Ledger.Transfer{
      ...>             to: "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD",
      ...>             amount: 30
      ...>           }
      ...>         ]
      ...>       }
      ...>     }
      ...>  },
      ...>  previous_public_key: "00EE9EBD56635EFA6C6382747CEC9B4B7E52B3E3CFF8B7A16077AC47E48EC06D38",
      ...>  previous_signature: "4DB9FF771458F8DBCB8CC18101DFF133E60BF99B0A09C25275422B0787BA6597C567F7F27D21D55FE1B211798F17543A7466D27F2F11CD64D802E526AAC19E06",
      ...>  origin_signature: "DA9252B7B0975B4208C80008817D9CE3F8BC7E3785D3CF3175D4BA248A55220F838F19742285A5F397F3350A8BFF779FB3F58AC078D4904557C973CEAE490904"
      ...> }
      iex> UnirisElection.HeuristicConstraints.validation_number(tx)
      8
  """
  @spec validation_number(Transaction.pending()) :: non_neg_integer()
  def validation_number(tx = %Transaction{}) do
    case tx.data.ledger.uco do
      %UCOLedger{transfers: transfers} when is_list(transfers) and length(transfers) > 0 ->
        total_transfers = Enum.map(transfers, & &1.amount) |> Enum.sum()

        if total_transfers > 10 do
          :math.floor(@min_validations * :math.log10(total_transfers)) |> trunc
        else
          @min_validations
        end

      _ ->
        @min_validations
    end
  end

  @doc """
  Require number of storages nodes for a given list of nodes according to their
  availability.

  To support data availability, cumulative average availability
  should be greater than `2^(log10(n)+5)`.

  From 143 nodes the number replicas start to reduce from the number of nodes.
  Just to ensure some stability in the network the sharding can evolve and later on the
  `HypergeometricDistribution` could be used instead to reduce to ~~200 nodes.

  ## Examples

      iex> UnirisElection.HeuristicConstraints.number_replicas(Enum.map(0..99, fn _ ->
      ...>  %{average_availability: 1}
      ...> end))
      100

      iex> UnirisElection.HeuristicConstraints.number_replicas(Enum.map(0..144, fn _ ->
      ...>  %{average_availability: 1}
      ...> end))
      143

      iex> UnirisElection.HeuristicConstraints.number_replicas(Enum.map(0..200, fn _ ->
      ...>  %{average_availability: 1}
      ...> end))
      158
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
