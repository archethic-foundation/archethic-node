defmodule Uniris.Account do
  @moduledoc false

  alias __MODULE__.MemTables.UCOLedger
  alias __MODULE__.MemTablesLoader

  @doc """
  Returns the balance for an address using the unspent outputs
  """
  @spec get_balance(Crypto.versioned_hash()) :: float()
  def get_balance(address) when is_binary(address) do
    address
    |> UCOLedger.get_unspent_outputs()
    |> Enum.reduce(0.0, &(&2 + &1.amount))
  end

  @doc """
  List all the unspent outputs for a given address
  """
  @spec get_unspent_outputs(binary()) :: list(UnspentOutput.t())
  defdelegate get_unspent_outputs(address), to: UCOLedger

  @doc """
  List all the inputs for a given transaction (including the spend/unspent inputs)
  """
  @spec get_inputs(binary()) :: list(TransactionInput.t())
  defdelegate get_inputs(address), to: UCOLedger, as: :get_inputs

  @doc """
  Load the transaction into the Account context filling the memory tables for ledgers
  """
  @spec load_transaction(Transaction.t()) :: :ok
  defdelegate load_transaction(transaction), to: MemTablesLoader
end
