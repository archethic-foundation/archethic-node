defmodule Archethic.Contracts.WasmContract do
  @moduledoc """
  Represents a smart contract using WebAssembly
  """

  alias Archethic.Contracts.Contract.State
  alias Archethic.Contracts.WasmModule
  alias Archethic.Contracts.WasmSpec
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Contract
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  require Logger

  defstruct version: 1,
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
          module: nil | WasmModule.t(),
          state: State.t(),
          transaction: Transaction.t()
        }

  @doc """
  Create a contract from a transaction. Same `from_transaction/1` but throws if the contract's code is invalid
  """
  @spec from_transaction!(Transaction.t()) :: t()
  def from_transaction!(tx = %Transaction{}) do
    case from_transaction(tx) do
      {:ok, contract} -> contract
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Validate WASM contract
  """
  @spec validate_and_parse(t()) :: {:ok, t()} | {:error, String.t()}
  def validate_and_parse(%Contract{manifest: manifest, bytecode: bytecode}) do
    uncompressed_bytes = :zlib.unzip(bytecode)

    with :ok <- WasmSpec.validate_manifest(manifest),
         spec = WasmSpec.from_manifest(manifest),
         {:ok, module} <- WasmModule.parse(uncompressed_bytes, spec) do
      {:ok, %__MODULE__{module: module}}
    end
  rescue
    ErlangError -> {:error, "invalid bytecode"}
  end

  @doc """
  Create a contract from a transaction
  """
  @spec from_transaction(Transaction.t()) :: {:ok, t()} | {:error, String.t()}
  def from_transaction(%Transaction{data: %TransactionData{contract: nil}}),
    do: {:error, "No contract to parse"}

  def from_transaction(tx = %Transaction{data: %TransactionData{contract: contract}}) do
    {:ok, %__MODULE__{parse(contract) | state: get_state_from_tx(tx), transaction: tx}}
  end

  defp parse(%Contract{manifest: manifest, bytecode: bytecode}) do
    uncompressed_bytes = :zlib.unzip(bytecode)
    spec = WasmSpec.from_manifest(manifest)

    {:ok, module} = WasmModule.parse(uncompressed_bytes, spec)
    %__MODULE__{module: module}
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
end
