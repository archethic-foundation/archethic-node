defmodule UnirisCore.Transaction.ValidationStamp.LedgerMovements do
  @moduledoc """
  Represents the ledger movements from the transaction's issuer applying the UTXO model with a previous status and a next status
  """

  alias __MODULE__.UTXO
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.TransactionData.Ledger.Transfer

  defstruct uco: %UTXO{}

  @typedoc """
  Ledger movements from the transaction's issuer.
  It represents the summary of the UTXO transfer
  - previous: contains the previous unspent outputs sender and the previous balance aggregated between the previous balance + sum of the unspent outputs asset transfered
  - next: the next balance
  """
  @type t :: %__MODULE__{
          uco: UTXO.t() | :unsufficient_funds
        }

  @spec new(
          tx :: Transaction.pending(),
          fee :: float(),
          previous_ledger :: __MODULE__.t(),
          unspent_outputs :: list(Transaction.validated())
        ) :: __MODULE__.t() | :unsufficient_funds
  def new(
        tx = %Transaction{},
        fee,
        _previous_ledger = %__MODULE__{uco: %UTXO{next: previous_uco_balance}},
        unspent_outputs
      ) do
    case next_uco_ledger(tx, fee, previous_uco_balance, unspent_outputs) do
      {:ok, uco_ledger} ->
        %__MODULE__{uco: uco_ledger}

      {:error, :unsufficient_uco} ->
        %__MODULE__{uco: :unsufficient_funds}
    end
  end

  # Produces a new UCO ledger based on the transaction transfers, the fee, the previous balance from the previous ledger and the unspent outputs transactions.
  # The next ledger holds:
  # - the previous unspent outputs froms and the total amount from the previous balance and the unspent outputs
  # - the next balance
  # to respect the UTXO model of each transaction.
  defp next_uco_ledger(
         %Transaction{data: %{ledger: %{uco: %{transfers: uco_transfers}}}},
         fee,
         previous_balance,
         unspent_outputs
       )
       when length(uco_transfers) > 0 do
    %{senders: senders, uco_received: uco_received} = reduce_unspent_outputs(unspent_outputs)
    uco_to_spend = Enum.reduce(uco_transfers, 0.0, fn %{amount: amount}, acc -> acc + amount end)

    current_balance = uco_received + previous_balance
    uco_to_spend = uco_to_spend + fee

    if current_balance >= uco_to_spend do
      {:ok,
       %UTXO{
         previous: %{from: senders, amount: current_balance},
         next: current_balance - uco_to_spend
       }}
    else
      {:error, :unsufficient_uco}
    end
  end

  defp next_uco_ledger(
         _,
         fee,
         previous_balance,
         unspent_outputs
       ) do
    %{senders: senders, uco_received: uco_received} = reduce_unspent_outputs(unspent_outputs)
    current_balance = uco_received + previous_balance

    if current_balance >= fee do
      {:ok,
       %UTXO{
         previous: %{from: senders, amount: current_balance},
         next: current_balance - fee
       }}
    else
      {:error, :unsufficient_uco}
    end
  end

  # Aggregate a list of unspent outputs to extract the senders and the
  # total amount transfers
  defp reduce_unspent_outputs(utxos, acc \\ %{senders: [], uco_received: 0.0})

  defp reduce_unspent_outputs([utxo | rest], acc) do
    uco_received = sum_of_transfered_uco(utxo)

    acc =
      acc
      |> Map.update!(:senders, &(&1 ++ [utxo.address]))
      |> Map.update!(:uco_received, &(&1 + uco_received))

    reduce_unspent_outputs(rest, acc)
  end

  defp reduce_unspent_outputs([], acc), do: acc

  defp sum_of_transfered_uco(%Transaction{
         data: %TransactionData{
           ledger: %Ledger{
             uco: %UCOLedger{transfers: transfers}
           }
         }
       }) do
    Enum.reduce(transfers, 0.0, fn %Transfer{amount: amount}, acc -> acc + amount end)
  end

  defp sum_of_transfered_uco(_), do: 0.0
end
