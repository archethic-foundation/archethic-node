defmodule Archethic.Contracts.WasmContract do
  @moduledoc """
  Represents a smart contract using WebAssembly
  """

  alias Archethic.Contracts.Contract.State
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.Contracts.WasmModule
  alias Archethic.Contracts.WasmSpec

  require Logger

  defstruct version: 2,
            module: nil,
            state: %{},
            transaction: %Transaction{}

  @type trigger_type() ::
          :oracle
          | {:transaction, String.t(), nil}
          | {:datetime, DateTime.t()}
          | {:interval, String.t()}

  @type trigger_key() ::
          :oracle
          | trigger_recipient()
          | {:datetime, DateTime.t()}
          | {:interval, String.t()}

  @type trigger_recipient :: {:transaction, nil | String.t(), nil | non_neg_integer()}

  @type t() :: %__MODULE__{
          version: integer(),
          module: WasmModule.t(),
          state: State.t(),
          transaction: Transaction.t()
        }

  @doc """
  Create a contract from a transaction. Same `from_transaction/1` but throws if the contract's code is invalid
  """
  @spec from_transaction!(Transaction.t()) :: t()
  def from_transaction!(tx) do
    case from_transaction(tx) do
      {:ok, contract} ->
        contract

      {:error, reason} ->
        raise reason
    end
  end

  @doc """
  Create a contract from a transaction
  """
  @spec from_transaction(Transaction.t()) :: {:ok, t()} | {:error, String.t()}
  def from_transaction(tx = %Transaction{data: %TransactionData{code: code, content: content}}) do
    with {:ok, manifest_json} <- Jason.decode(content),
         spec = WasmSpec.from_manifest(manifest_json),
         {:ok, module} <- WasmModule.parse(code, spec) do
      contract = %__MODULE__{
        module: module,
        state: get_state_from_tx(tx),
        transaction: tx
      }

      {:ok, contract}
    else
      {:error, reason} ->
        {:error, "#{inspect(reason)}"}
    end
  end

  defp get_state_from_tx(%Transaction{
         validation_stamp: %ValidationStamp{
           ledger_operations: %LedgerOperations{unspent_outputs: utxos}
         }
       }) do
    case Enum.find(utxos, &(&1.type == :state)) do
      %UnspentOutput{encoded_payload: encoded_state} ->
        {state, _rest} = State.deserialize(encoded_state)
        state

      nil ->
        State.empty()
    end
  end

  defp get_state_from_tx(_), do: State.empty()

  @doc """
  Return true if the contract contains at least one trigger
  """
  @spec contains_trigger?(contract :: t()) :: boolean()
  def contains_trigger?(%__MODULE__{module: %WasmModule{spec: %WasmSpec{triggers: triggers}}}),
    do: length(triggers) > 0

  @doc """
  Return the args names for this recipient or nil
  """
  def get_trigger_for_recipient(%Recipient{action: action, args: _args_values}),
    do: {:transaction, action, nil}
end
