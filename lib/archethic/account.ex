defmodule Archethic.Account do
  @moduledoc false

  alias __MODULE__.MemTables.TokenLedger
  alias __MODULE__.MemTables.UCOLedger
  alias __MODULE__.MemTables.StateLedger
  alias __MODULE__.MemTables.GenesisInputLedger
  alias __MODULE__.MemTablesLoader

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionInput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.VersionedTransactionInput

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
      %VersionedUnspentOutput{unspent_output: %UnspentOutput{type: :UCO, amount: amount}}, acc ->
        Map.update!(acc, :uco, &(&1 + amount))

      %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{type: {:token, token_address, token_id}, amount: amount}
      },
      acc ->
        update_in(acc, [:token, Access.key({token_address, token_id}, 0)], &(&1 + amount))

      _, acc ->
        acc
    end)
  end

  @doc """
  List all the unspent outputs for a given address
  """
  @spec get_unspent_outputs(binary()) :: list(VersionedUnspentOutput.t())
  def get_unspent_outputs(address) when is_binary(address) do
    uco_tokens_utxos =
      UCOLedger.get_unspent_outputs(address) ++ TokenLedger.get_unspent_outputs(address)

    case StateLedger.get_unspent_output(address) do
      nil ->
        uco_tokens_utxos

      state_utxo ->
        [state_utxo | uco_tokens_utxos]
    end
  end

  @doc """
  List all the inputs for a given transaction (including the spend/unspent inputs)
  """
  @spec get_inputs(binary()) :: list(VersionedTransactionInput.t())
  def get_inputs(address) do
    UCOLedger.get_inputs(address) ++ TokenLedger.get_inputs(address)
  end

  @doc """
  Load the transaction into the Account context filling the memory tables for ledgers
  """
  @spec load_transaction(Transaction.t(), opts :: MemTablesLoader.load_options()) :: :ok
  defdelegate load_transaction(transaction, io_transaction?), to: MemTablesLoader

  @doc """
  Returns the list of all the inputs which have not been consumed for the given chain's address
  """
  @spec get_genesis_unspent_inputs(binary()) :: list(TransactionInput.t())
  defdelegate get_genesis_unspent_inputs(address), to: GenesisInputLedger, as: :get_unspent_inputs
end
