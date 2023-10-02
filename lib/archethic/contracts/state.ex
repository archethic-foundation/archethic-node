defmodule Archethic.Contracts.State do
  @moduledoc """
  Module to manipulate the contract state
  """
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  @type t() :: map()

  @spec empty() :: t()
  def empty() do
    %{}
  end

  @doc """
  Extract the state from a validated transaction (nil if none)
  """
  @spec get_utxo_from_transaction(Transaction.t()) :: nil | UnspentOutput.t()
  def get_utxo_from_transaction(%Transaction{
        validation_stamp: %ValidationStamp{
          ledger_operations: %LedgerOperations{unspent_outputs: unspent_outputs}
        }
      }) do
    Enum.find(unspent_outputs, &(&1.type == :state))
  end

  @doc """
  Extract the state from an unspent output
  Return an empty state if nil given
  """
  @spec from_utxo(nil | UnspentOutput.t()) :: t()
  def from_utxo(nil), do: empty()

  def from_utxo(%UnspentOutput{type: :state, encoded_payload: encoded_payload}) do
    # FIXME: real implemnetation
    encoded_payload
    |> :erlang.binary_to_term()
  end

  @doc """
  Return either
    nil (if the state is empty)
    the state encoded in an utxo
  """
  @spec to_utxo(t()) :: nil | UnspentOutput.t()
  def to_utxo(state = %{}) do
    if state == empty() do
      nil
    else
      # FIXME: real implementation
      %UnspentOutput{
        type: :state,
        encoded_payload:
          state
          |> :erlang.term_to_binary()
      }
    end
  end
end
