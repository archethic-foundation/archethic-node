defmodule Archethic.Contracts.ContractV2 do
  @moduledoc """
  Represents a smart contract
  """

  alias Archethic.Contracts.Contract.State
  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.Contracts.WasmInstance
  alias Archethic.Contracts.WasmSpec

  require Logger

  defstruct version: 2,
            instance: nil,
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
          instance: pid(),
          state: State.t(),
          transaction: Transaction.t()
        }

  @doc """
  Create a contract from a transaction. Same `from_transaction/1` but throws if the contract's code is invalid
  """
  @spec from_transaction!(Transaction.t()) :: t()
  def from_transaction!(tx) do
    {:ok, contract} = from_transaction(tx)
    contract
  end

  @doc """
  Create a contract from a transaction
  """
  @spec from_transaction(Transaction.t()) :: {:ok, t()} | {:error, String.t()}
  def from_transaction(tx = %Transaction{data: %TransactionData{code: code}}) do
    case WasmInstance.start_link(bytes: code, transaction: tx) do
      {:ok, instance_pid} ->
        contract = %__MODULE__{
          instance: instance_pid,
          state: get_state_from_tx(tx),
          transaction: tx
        }

        {:ok, contract}

      {:error, _} = e ->
        e
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

  @doc """
  Return true if the contract contains at least one trigger
  """
  @spec contains_trigger?(contract :: t()) :: boolean()
  def contains_trigger?(%__MODULE__{instance: instance}) do
    %WasmSpec{triggers: triggers} = WasmInstance.spec(instance)
    length(triggers) > 0
  end

  @doc """
  Return the args names for this recipient or nil
  """
  def get_trigger_for_recipient(%Recipient{action: action, args: _args_values}),
    do: {:transaction, action, nil}

  @doc """
  Add seed ownership to transaction (on contract version != 0)
  Sign a next transaction in the contract chain
  """
  @spec sign_next_transaction(
          contract :: t(),
          next_tx :: Transaction.t(),
          index :: non_neg_integer()
        ) :: {:ok, Transaction.t()} | {:error, :decryption_failed}
  def sign_next_transaction(
        %__MODULE__{
          transaction:
            prev_tx = %Transaction{previous_public_key: previous_public_key, address: address}
        },
        %Transaction{type: next_type, data: next_data},
        index
      ) do
    case get_contract_seed(prev_tx) do
      {:ok, contract_seed} ->
        ownership = create_new_seed_ownership(contract_seed)
        next_data = Map.update(next_data, :ownerships, [ownership], &[ownership | &1])

        signed_tx =
          Transaction.new(
            next_type,
            next_data,
            contract_seed,
            index,
            Crypto.get_public_key_curve(previous_public_key),
            Crypto.get_public_key_origin(previous_public_key)
          )

        {:ok, signed_tx}

      error ->
        Logger.debug("Cannot decrypt the transaction seed", contract: Base.encode16(address))
        error
    end
  end

  defp get_seed_ownership(
         %Transaction{data: %TransactionData{ownerships: ownerships}},
         storage_nonce_public_key
       ) do
    Enum.find(ownerships, &Ownership.authorized_public_key?(&1, storage_nonce_public_key))
  end

  defp get_contract_seed(tx) do
    storage_nonce_public_key = Crypto.storage_nonce_public_key()

    ownership = %Ownership{secret: secret} = get_seed_ownership(tx, storage_nonce_public_key)

    encrypted_key = Ownership.get_encrypted_key(ownership, storage_nonce_public_key)

    case Crypto.ec_decrypt_with_storage_nonce(encrypted_key) do
      {:ok, aes_key} -> Crypto.aes_decrypt(secret, aes_key)
      {:error, :decryption_failed} -> {:error, :decryption_failed}
    end
  end

  defp create_new_seed_ownership(seed) do
    storage_nonce_pub_key = Crypto.storage_nonce_public_key()

    aes_key = :crypto.strong_rand_bytes(32)
    secret = Crypto.aes_encrypt(seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, storage_nonce_pub_key)

    %Ownership{secret: secret, authorized_keys: %{storage_nonce_pub_key => encrypted_key}}
  end

  @doc """
  Remove the seed ownership of a contract transaction
  """
  @spec remove_seed_ownership(tx :: Transaction.t()) :: Transaction.t()
  def remove_seed_ownership(tx) do
    storage_nonce_public_key = Crypto.storage_nonce_public_key()

    update_in(tx, [Access.key!(:data), Access.key!(:ownerships)], fn ownerships ->
      case Enum.find_index(
             ownerships,
             &Ownership.authorized_public_key?(&1, storage_nonce_public_key)
           ) do
        nil -> ownerships
        index -> List.delete_at(ownerships, index)
      end
    end)
  end

  @doc """
  Same as remove_seed_ownership but raise if no ownership matches contract seed
  """
  @spec remove_seed_ownership!(tx :: Transaction.t()) :: Transaction.t()
  def remove_seed_ownership!(tx) do
    case remove_seed_ownership(tx) do
      ^tx -> raise "Contract does not have seed ownership"
      tx -> tx
    end
  end

  @doc """
  Return the encrypted seed and encrypted aes key
  """
  @spec get_encrypted_seed(contract :: t()) :: {binary(), binary()} | nil
  def get_encrypted_seed(%__MODULE__{transaction: tx}) do
    storage_nonce_public_key = Crypto.storage_nonce_public_key()

    case get_seed_ownership(tx, storage_nonce_public_key) do
      %Ownership{secret: secret, authorized_keys: authorized_keys} ->
        encrypted_key = Map.get(authorized_keys, storage_nonce_public_key)

        {secret, encrypted_key}

      nil ->
        nil
    end
  end
end
