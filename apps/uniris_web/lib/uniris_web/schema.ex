defmodule UnirisWeb.Schema do
  @moduledoc false

  use Absinthe.Schema

  alias UnirisCore.Storage
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.TransactionData.Ledger.Transfer
  alias UnirisCore.TransactionData.Keys
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.NodeMovements
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements.UTXO

  import_types(__MODULE__.TransactionType)

  query do
    field :transaction, :transaction do
      arg(:address, :hash)

      resolve(fn %{address: address}, _ ->
        with {:ok, tx} <- UnirisCore.search_transaction(address) do
          {:ok, format(tx)}
        end
      end)
    end

    field :transactions, list_of(:transaction) do
      resolve(fn _, _ ->
        {:ok, Storage.list_transactions() |> Enum.map(&format/1)}
      end)
    end
  end

  mutation do
    field :new_transaction, :boolean do
      arg(:address, non_null(:hash))
      arg(:timestamp, non_null(:integer))
      arg(:type, non_null(:transaction_type))
      arg(:data, non_null(:transaction_data_input))
      arg(:previous_public_key, non_null(:public_key))
      arg(:previous_signature, non_null(:signature))
      arg(:origin_signature, non_null(:signature))

      resolve(fn tx, _ ->
        tx = struct(Transaction, tx)
        :ok = UnirisCore.send_new_transaction(tx)
        {:ok, true}
      end)
    end
  end

  subscription do
    field :new_transaction, :transaction do
      config(fn _args, _info ->
        {:ok, topic: "*"}
      end)

      resolve(fn address, _, _ ->
        case UnirisCore.search_transaction(address) do
          {:ok, tx} ->
            {:ok, format(tx)}
        end
      end)
    end

    field :acknowledge_storage, :transaction do
      arg(:address, non_null(:hash))

      config(fn args, _info ->
        {:ok, topic: args.address}
      end)

      resolve(fn address, _, _ ->
        case UnirisCore.search_transaction(address) do
          {:ok, tx} ->
            {:ok, format(tx)}
        end
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
         ledger_movements: ledger_movements,
         node_movements: node_movements,
         signature: signature
       }) do
    %{
      proof_of_work: pow,
      proof_of_integrity: poi,
      ledger_movements: format(ledger_movements),
      node_movements: format(node_movements),
      signature: signature
    }
  end

  defp format(%LedgerMovements{uco: uco_ledger}) do
    %{
      uco: format(uco_ledger)
    }
  end

  defp format(%UTXO{previous: %{from: from, amount: amount}, next: next}) do
    %{
      previous: %{
        from: from,
        amount: amount
      },
      next: next
    }
  end

  defp format(%NodeMovements{fee: fee, rewards: rewards}) do
    %{
      fee: fee,
      rewards: format(rewards)
    }
  end

  defp format(list) when is_list(list) do
    Enum.map(list, &format(&1))
  end

  defp format({key, amount}) do
    %{
      node: key,
      amount: amount
    }
  end

  defp format({sig, inconsistencies, public_key}) do
    %{
      node: public_key,
      signature: sig,
      inconsistencies: inconsistencies
    }
  end
end
