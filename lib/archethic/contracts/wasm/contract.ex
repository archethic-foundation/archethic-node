defmodule Archethic.Contracts.WasmContract do
  @moduledoc """
  Represents a smart contract using WebAssembly
  """

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract.State
  alias Archethic.Contracts.WasmModule
  alias Archethic.Contracts.WasmSpec
  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

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
  def from_transaction!(tx = %Transaction{}) do
    case from_transaction(tx) do
      {:ok, contract} ->
        contract

      {:error, reason} ->
        raise reason
    end
  end

  @doc """
  Parse smart contract json block and return a contract struct
  """
  @spec parse(contract :: map()) ::
          {:ok, t()} | {:error, String.t()}
  def parse(%{manifest: manifest_json, bytecode: bytecode}) do
    with {:ok, manifest} <- Jason.decode(manifest_json),
         :ok <- WasmSpec.validate_manifest(manifest),
         uncompressed_bytes = :zlib.unzip(bytecode),
         spec = WasmSpec.from_manifest(manifest),
         {:ok, module} <- WasmModule.parse(uncompressed_bytes, spec) do
      {:ok, %__MODULE__{module: module}}
    else
      {:error, reason} -> {:error, "#{inspect(reason)}"}
    end
  end

  @doc """
  Create a contract from a transaction
  """
  @spec from_transaction(Transaction.t()) :: {:ok, t()} | {:error, String.t()}
  def from_transaction(tx = %Transaction{data: %TransactionData{contract: contract}})
      when contract != nil do
    case parse(contract) do
      {:ok, contract} ->
        {:ok, %{contract | state: get_state_from_tx(tx), transaction: tx}}

      {:error, _} = e ->
        e
    end
  end

  def from_transaction(%Transaction{data: %TransactionData{contract: nil}}),
    do: {:error, "No contract to parse"}

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

  @doc """
  Return the encrypted seed and encrypted aes key
  """
  @spec get_encrypted_seed(contract :: t()) :: binary() | nil
  def get_encrypted_seed(%__MODULE__{transaction: tx}) do
    storage_nonce_public_key = Crypto.storage_nonce_public_key()

    case Contracts.get_seed_ownership(tx, storage_nonce_public_key) do
      %Ownership{secret: secret, authorized_keys: authorized_keys} ->
        encrypted_key = Map.get(authorized_keys, storage_nonce_public_key)

        with {:ok, aes_key} <- Crypto.ec_decrypt_with_storage_nonce(encrypted_key),
             {:ok, seed} <- Crypto.aes_decrypt(secret, aes_key) do
          seed
        else
          _ ->
            nil
        end

      nil ->
        nil
    end
  end
end
