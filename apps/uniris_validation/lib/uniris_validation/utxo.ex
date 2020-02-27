defmodule UnirisValidation.UTXO do
  @moduledoc false

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements.UTXO

  @doc """
  Compute the next UTXO ledger from the transaction, the transaction fee, the previous ledger movements and the list of unspent outputs

  ## Examples

     iex> tx = %UnirisChain.Transaction{
     ...>   address: "338D4F0D969ABCE1AC1975976D54256ED1725D9A7AF7D6F2DCF56FD26B1E4F1E",
     ...>   type: :transfer,
     ...>   timestamp: DateTime.utc_now(),
     ...>   data: %{
     ...>     ledger: %{
     ...>       uco: %{
     ...>         transfers: [%{to: "", amount: 10}]
     ...>       }
     ...>     }
     ...>   },
     ...>   previous_public_key: "",
     ...>   previous_signature: "",
     ...>   origin_signature: ""
     ...> }
     ...> unspent_output_transactions = [%UnirisChain.Transaction{
     ...>   address: "69D4E94B8105BE3B7C52590D4888D6EC8C1D9C0FED0FB2F89DA28D5A1A9213E4",
     ...>   type: :transfer,
     ...>   timestamp: DateTime.utc_now(),
     ...>   data: %{
     ...>     ledger: %{
     ...>       uco: %{
     ...>         transfers: [%{to: "338D4F0D969ABCE1AC1975976D54256ED1725D9A7AF7D6F2DCF56FD26B1E4F1E", amount: 12}]
     ...>       }
     ...>     }
     ...>   },
     ...>   previous_public_key: "",
     ...>   previous_signature: "",
     ...>   origin_signature: ""
     ...> }]
     ...> UnirisValidation.UTXO.next_ledger(tx, 1.0, %UnirisChain.Transaction.ValidationStamp.LedgerMovements{}, unspent_output_transactions)
     {
       :ok,
       %UnirisChain.Transaction.ValidationStamp.LedgerMovements{
          nft: nil,
          uco: %UnirisChain.Transaction.ValidationStamp.LedgerMovements.UTXO{
             previous: %{
               from: ["69D4E94B8105BE3B7C52590D4888D6EC8C1D9C0FED0FB2F89DA28D5A1A9213E4"],
               amount: 12
             },
             next: 1.0
          }
       }
     }


  Returns `{:error, :unsufficient_funds}` when the amount of assets + fee to transfers is greater than
  the previous balance + total of unspent output transactions assets transfered
  """
  @spec next_ledger(
          Transaction.pending(),
          float(),
          LedgerMovements.t(),
          list(Transaction.validated())
        ) :: {:ok, LedgerMovements.t()} | {:error, :unsufficients_funds}
  def next_ledger(
        %Transaction{},
        _fee,
        _previous_ledger = %LedgerMovements{uco: %{next: 0}},
        []
      ) do
    {:error, :unsufficients_funds}
  end

  def next_ledger(
        %Transaction{data: %{ledger: %{uco: %{transfers: uco_transfers}}}},
        fee,
        %LedgerMovements{uco: %{next: previous_uco_balance}},
        unspent_output_transactions
      ) do
    if length(uco_transfers) > 0 do
      {:ok,
       %LedgerMovements{
         uco:
           next_uco_ledger(uco_transfers, fee, previous_uco_balance, unspent_output_transactions)
       }}
    end
  end

  @doc """
  Produces a new UCO ledger based on the transaction transfers, the fee, the previous balance from the previous ledger and the unspent outputs transactions.

  The next ledger holds:
  - the previous unspent outputs froms and the total amount from the previous balance and the unspent outputs
  - the next balance
  to respect the UTXO model of each transaction.
  """
  def next_uco_ledger(uco_transfers, fee, previous_balance, unspent_outputs) do
    %{senders: senders, uco_received: uco_received} = reduce_unspent_outputs(unspent_outputs)
    uco_to_spend = Enum.reduce(uco_transfers, 0, fn %{amount: amount}, acc -> acc + amount end)

    current_balance = uco_received + previous_balance
    uco_to_spend = uco_to_spend + fee

    if current_balance >= uco_to_spend do
      %UTXO{
        previous: %{from: senders, amount: current_balance},
        next: current_balance - uco_to_spend
      }
    else
      {:error, :unsufficient_uco}
    end
  end

  # Aggregate a list of unspent outputs to extract the senders and the
  # total amount transfers
  defp reduce_unspent_outputs(unspent_outputs) do
    unspent_outputs
    |> Enum.reduce(%{senders: [], uco_received: 0}, fn tx, acc ->
      uco_received = Enum.reduce(tx.data.ledger.uco.transfers, 0, &(&2 + &1.amount))

      acc
      |> Map.update!(:senders, &(&1 ++ [tx.address]))
      |> Map.update!(:uco_received, &(&1 + uco_received))
    end)
  end
end
