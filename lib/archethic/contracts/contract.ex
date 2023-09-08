defmodule Archethic.Contracts.Contract do
  @moduledoc """
  Represents a smart contract
  """

  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.ContractConditions.Subjects, as: ConditionsSubjects

  alias Archethic.Contracts.Interpreter

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.Recipient

  require Logger

  defstruct triggers: %{},
            functions: %{},
            version: 0,
            conditions: %{},
            transaction: %Transaction{}

  @type trigger_type() ::
          :oracle
          | {:transaction, nil, nil}
          | {:transaction, String.t(), list(String.t())}
          | {:datetime, DateTime.t()}
          | {:interval, String.t()}

  @type condition_type() ::
          :oracle
          | :inherit
          | {:transaction, nil, nil}
          | {:transaction, String.t(), list(String.t())}

  @type trigger_key() ::
          :oracle
          | {:transaction, nil, nil}
          | {:transaction, String.t(), non_neg_integer()}
          | {:datetime, DateTime.t()}
          | {:interval, String.t()}

  @type condition_key() ::
          :oracle
          | :inherit
          | {:transaction, nil, nil}
          | {:transaction, String.t(), non_neg_integer()}

  @type t() :: %__MODULE__{
          triggers: %{trigger_key() => %{args: list(binary()), ast: Macro.t()}},
          version: integer(),
          conditions: %{condition_key() => Conditions.t()},
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
    case Interpreter.parse(code) do
      {:ok, contract} -> {:ok, contract |> Map.put(:transaction, tx)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Add a trigger to the contract
  """
  @spec add_trigger(t(), trigger_type(), any()) :: t()
  def add_trigger(contract, type, actions) do
    trigger_key = get_key(type)
    actions = get_actions(type, actions)

    Map.update!(contract, :triggers, &Map.put(&1, trigger_key, actions))
  end

  @doc """
  Add a condition to the contract
  """
  @spec add_condition(map(), condition_type(), ConditionsSubjects.t()) :: t()
  def add_condition(contract, condition_type, conditions) do
    condition_key = get_key(condition_type)
    conditions = get_conditions(condition_type, conditions)

    Map.update!(contract, :conditions, &Map.put(&1, condition_key, conditions))
  end

  defp get_key({:transaction, action, args}) when is_list(args),
    do: {:transaction, action, length(args)}

  defp get_key(key), do: key

  defp get_conditions({:transaction, _action, args}, conditions) when is_list(args),
    do: %Conditions{args: args, subjects: conditions}

  defp get_conditions(_, conditions), do: %Conditions{subjects: conditions}

  defp get_actions({:transaction, _action, args}, ast) when is_list(args),
    do: %{args: args, ast: ast}

  defp get_actions(_, conditions), do: %{args: [], ast: conditions}

  @doc """
  Add a public or private function to the contract
  """
  @spec add_function(
          contract :: t(),
          function_name :: binary(),
          ast :: any(),
          args :: list(),
          visibility :: atom()
        ) :: t()
  def add_function(
        contract = %__MODULE__{},
        function_name,
        ast,
        args,
        visibility
      ) do
    Map.update!(
      contract,
      :functions,
      &Map.put(&1, {function_name, length(args)}, %{args: args, ast: ast, visibility: visibility})
    )
  end

  @doc """
  Return the args names for this recipient or nil
  """
  @spec get_trigger_for_recipient(Recipient.t()) :: nil | trigger_key()
  def get_trigger_for_recipient(%Recipient{action: nil, args: nil}), do: {:transaction, nil, nil}

  def get_trigger_for_recipient(%Recipient{action: action, args: args_values}),
    do: {:transaction, action, length(args_values)}

  @doc """
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
        signed_tx =
          Transaction.new(
            next_type,
            next_data,
            contract_seed,
            index,
            Crypto.get_public_key_curve(previous_public_key)
          )

        {:ok, signed_tx}

      error ->
        Logger.debug("Cannot decrypt the transaction seed", contract: Base.encode16(address))
        error
    end
  end

  defp get_contract_seed(%Transaction{data: %TransactionData{ownerships: ownerships}}) do
    storage_nonce_public_key = Crypto.storage_nonce_public_key()

    %Ownership{secret: secret, authorized_keys: authorized_keys} =
      Enum.find(ownerships, &Ownership.authorized_public_key?(&1, storage_nonce_public_key))

    encrypted_key = Map.get(authorized_keys, storage_nonce_public_key)

    case Crypto.ec_decrypt_with_storage_nonce(encrypted_key) do
      {:ok, aes_key} -> Crypto.aes_decrypt(secret, aes_key)
      {:error, :decryption_failed} -> {:error, :decryption_failed}
    end
  end
end
