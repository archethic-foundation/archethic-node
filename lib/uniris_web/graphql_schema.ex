defmodule UnirisWeb.GraphQLSchema do
  @moduledoc false

  use Absinthe.Schema

  alias Uniris.Storage

  alias Uniris.Transaction
  alias Uniris.Transaction.CrossValidationStamp
  alias Uniris.Transaction.ValidationStamp
  alias Uniris.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionInput

  alias Uniris.TransactionData
  alias Uniris.TransactionData.Keys
  alias Uniris.TransactionData.Ledger
  alias Uniris.TransactionData.Ledger.Transfer
  alias Uniris.TransactionData.UCOLedger

  alias __MODULE__.TransactionType

  import_types(TransactionType)

  query do
    field :transaction, :transaction do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        with {:ok, tx} <- Uniris.search_transaction(address) do
          {:ok, format(tx)}
        end
      end)
    end

    field :last_transaction, :transaction do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        with {:ok, tx} <- Uniris.get_last_transaction(address) do
          {:ok, format(tx)}
        end
      end)
    end

    field :transactions, list_of(:transaction) do
      resolve(fn _, _ ->
        {:ok,
         Storage.list_transactions() |> Enum.reject(&(&1.type == :beacon)) |> Enum.map(&format/1)}
      end)
    end

    field :transaction_chain, list_of(:transaction) do
      arg(:address, non_null(:address))

      resolve(fn %{address: address}, _ ->
        chain =
          Uniris.get_transaction_chain(address)
          |> Enum.map(&format/1)

        {:ok, chain}
      end)
    end
  end

  subscription do
    field :new_transaction, :transaction do
      config(fn _args, _info ->
        {:ok, topic: "*"}
      end)

      resolve(fn address, _, _ ->
        case Uniris.search_transaction(address) do
          {:ok, tx} ->
            {:ok, format(tx)}
        end
      end)
    end

    field :acknowledge_storage, :transaction do
      arg(:address, non_null(:address))

      config(fn args, _info ->
        {:ok, topic: args.address}
      end)

      resolve(fn address, _, _ ->
        {:ok, tx} = Uniris.search_transaction(address)
        {:ok, format(tx)}
      end)
    end
  end

  defp format(tx = %Transaction{}) do
    %{
      address: tx.address,
      type: tx.type,
      timestamp: tx.timestamp,
      data: format(tx.data),
      previous_public_key: tx.previous_public_key,
      previous_signature: tx.previous_signature,
      origin_signature: tx.origin_signature,
      validation_stamp: format(tx.validation_stamp),
      cross_validation_stamps: format(tx.cross_validation_stamps)
    }
  end

  defp format(%TransactionData{
         content: content,
         code: code,
         ledger: ledger,
         keys: keys
       }) do
    %{
      content: content,
      code: code,
      ledger: format(ledger),
      keys: format(keys)
    }
  end

  defp format(%Ledger{uco: uco}) do
    %{
      uco: format(uco)
    }
  end

  defp format(%UCOLedger{fee: fee, transfers: transfers}) do
    %{
      fee: fee,
      transfers: format(transfers)
    }
  end

  defp format(%Transfer{to: to, amount: amount}) do
    %{
      to: to,
      amount: amount
    }
  end

  defp format(%Keys{secret: secret, authorized_keys: authorized_keys}) do
    %{
      secret: secret,
      authorized_keys:
        Enum.reduce(authorized_keys, [], fn {public_key, encrypted_key}, acc ->
          acc ++ [%{public_key: public_key, encrypted_key: encrypted_key}]
        end)
    }
  end

  defp format(%ValidationStamp{
         proof_of_work: pow,
         proof_of_integrity: poi,
         ledger_operations: ledger_operations,
         signature: signature
       }) do
    %{
      proof_of_work: pow,
      proof_of_integrity: poi,
      ledger_operations: format(ledger_operations),
      signature: signature
    }
  end

  defp format(%LedgerOperations{
         transaction_movements: transaction_movements,
         node_movements: node_movements,
         unspent_outputs: unspent_outputs,
         fee: fee
       }) do
    %{
      transaction_movements: format(transaction_movements),
      node_movements: format(node_movements),
      unspent_outputs: format(unspent_outputs),
      fee: fee
    }
  end

  defp format(%NodeMovement{to: to, amount: amount}) do
    %{
      to: to,
      amount: amount
    }
  end

  defp format(%TransactionMovement{to: to, amount: amount}) do
    %{
      to: to,
      amount: amount
    }
  end

  defp format(%UnspentOutput{from: from, amount: amount}) do
    %{
      from: from,
      amount: amount
    }
  end

  defp format(list) when is_list(list) do
    Enum.map(list, &format(&1))
  end

  defp format(%CrossValidationStamp{signature: signature, node_public_key: public_key}) do
    %{
      node: public_key,
      signature: signature
    }
  end

  defp format(%TransactionInput{amount: amount, from: from, spent?: spent?}) do
    %{
      amount: amount,
      from: from,
      spent?: spent?
    }
  end
end
