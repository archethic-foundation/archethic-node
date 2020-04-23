defmodule UnirisWeb.Schema do
  @moduledoc false

  use Absinthe.Schema

  alias UnirisCore.Election
  alias UnirisCore.Crypto
  alias UnirisCore.Storage
  alias UnirisCore.Transaction
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node

  import_types(__MODULE__.TransactionType)

  query do
    field :transaction, :transaction do
      arg(:address, :hash)

      resolve(fn %{address: address}, _ ->

        nearest_storage_nodes(address)
        |> P2P.send_message({:get_transaction, address})
        |> case do
          {:ok, tx} ->
            {:ok, format_transaction(tx)}

          _ ->
            {:error, :transaction_not_exists}
        end
      end)
    end

    field :transactions, list_of(:transaction) do
      resolve(fn _, _ ->
        {:ok, Storage.list_transactions() |> Enum.map(&format_transaction/1)}
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
        validation_nodes = Election.validation_nodes(tx)

        Enum.each(validation_nodes, fn node ->
          Task.start(fn ->
            P2P.send_message(
              node,
              {:start_mining, tx, Crypto.node_public_key(),
               Enum.map(validation_nodes, & &1.last_public_key)}
            )
          end)
        end)
        {:ok, true}
      end)
    end
  end

  subscription do
    field :new_transaction, :transaction do
      config fn _args, _info ->
        {:ok, topic: "*"}
      end
      resolve fn address, _, _ ->
        nearest_storage_nodes(address)
        |> P2P.send_message({:get_transaction, address})
        |> case do
          {:ok, tx} ->
            {:ok, format_transaction(tx)}
        end
      end
    end

    field :acknowledge_storage, :transaction do
      arg :address, non_null(:hash)
      config fn args, _info ->
        {:ok, topic: args.address}
      end
      resolve fn address, _, _ ->
        nearest_storage_nodes(address)
        |> P2P.send_message({:get_transaction, address})
        |> case do
          {:ok, tx} ->
            {:ok, format_transaction(tx)}
        end
      end
    end
  end

  defp nearest_storage_nodes(address) do
    %Node{network_patch: patch} = P2P.node_info()
    address
    |> Election.storage_nodes
    |> P2P.nearest_nodes(patch)
    |> List.first()
  end

  defp format_transaction(tx = %Transaction{}) do
    %{
      address: tx.address,
      type: tx.type,
      timestamp: tx.timestamp,
      data: tx.data,
      previous_public_key: tx.previous_public_key,
      previous_signature: tx.previous_signature,
      origin_signature: tx.origin_signature,
      validation_stamp: %{
        proof_of_work: tx.validation_stamp.proof_of_work,
        proof_of_integrity: tx.validation_stamp.proof_of_integrity,
        ledger_movements: %{
          uco: %{
            previous: %{
              from: tx.validation_stamp.ledger_movements.uco.previous.from,
              amount: tx.validation_stamp.ledger_movements.uco.previous.amount
            },
            next: tx.validation_stamp.ledger_movements.uco.next
          }
        },
        node_movements: %{
          fee: tx.validation_stamp.node_movements.fee,
          rewards:
            Enum.map(tx.validation_stamp.node_movements.rewards, fn {key, amount} ->
              %{
                node: key,
                amount: amount
              }
            end)
        },
        signature: tx.validation_stamp.signature
      },
      cross_validation_stamps:
        Enum.map(tx.cross_validation_stamps, fn {sig, inconsistencies, public_key} ->
          %{
            node: public_key,
            signature: sig,
            inconsistencies: inconsistencies
          }
        end)
    }
  end
end
