defmodule Archethic.Account do
  @moduledoc false

  alias __MODULE__.MemTables.TokenLedger
  alias __MODULE__.MemTables.UCOLedger
  alias __MODULE__.MemTablesLoader

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionInput

  @type balance :: %{
          uco: amount :: pos_integer(),
          token: %{
            {address :: binary(), token_id :: non_neg_integer()} => amount :: pos_integer()
          }
        }

  @doc """
  Returns the balance for an address using the unspent outputs
  """
  @spec get_balance(Crypto.versioned_hash()) :: balance()
  def get_balance(address) when is_binary(address) do
    address
    |> get_unspent_outputs()
    |> Enum.reduce(%{uco: 0, token: %{}}, fn
      %UnspentOutput{type: :UCO, amount: amount}, acc ->
        Map.update!(acc, :uco, &(&1 + amount))

      %UnspentOutput{type: {:token, token_address, token_id}, amount: amount}, acc ->
        update_in(acc, [:token, Access.key({token_address, token_id}, 0)], &(&1 + amount))
    end)
  end

  @doc """
  List all the unspent outputs for a given address
  """
  @spec get_unspent_outputs(binary()) :: list(UnspentOutput.t())
  def get_unspent_outputs(address) do
    UCOLedger.get_unspent_outputs(address) ++ TokenLedger.get_unspent_outputs(address)
  end

  @doc """
  List all the inputs for a given transaction (including the spend/unspent inputs)
  """
  @spec get_inputs(binary()) :: list(TransactionInput.t())
  def get_inputs(address) do
    UCOLedger.get_inputs(address) ++ TokenLedger.get_inputs(address)
  end

  @doc """
  Load the transaction into the Account context filling the memory tables for ledgers
  """
  @spec load_transaction(Transaction.t()) :: :ok
  defdelegate load_transaction(transaction), to: MemTablesLoader
end
