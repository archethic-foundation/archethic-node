defmodule ArchethicWeb.GraphQLSchema.Resolver do
  @moduledoc false

  alias Archethic

  alias Archethic.Crypto

  alias Archethic.P2P

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionInput

  @limit_page 10

  def get_balance(address) do
    case Archethic.get_balance(address) do
      {:ok, %{uco: uco, nft: nft_balances}} ->
        balance = %{
          uco: uco,
          nft:
            nft_balances
            |> Enum.map(fn {address, amount} -> %{address: address, amount: amount} end)
            |> Enum.sort_by(& &1.amount)
        }

        {:ok, balance}

      {:error, :network_issue} = e ->
        e
    end
  end

  def get_inputs(address) do
    case Archethic.get_transaction_inputs(address) do
      {:ok, inputs} ->
        {:ok, Enum.map(inputs, &TransactionInput.to_map/1)}

      {:error, _} = e ->
        e
    end
  end

  def shared_secrets do
    %{
      storage_nonce_public_key: Crypto.storage_nonce_public_key()
    }
  end

  def paginate_chain(address, page) do
    case Archethic.get_transaction_chain(address) do
      {:ok, chain} ->
        {:ok, paginate_transactions(chain, page)}

      {:error, _} = e ->
        e
    end
  end

  def paginate_local_transactions(page) do
    paginate_transactions(TransactionChain.list_all(), page)
  end

  defp paginate_transactions(transactions, page) do
    transactions
    |> Stream.map(&Transaction.to_map/1)
    |> Stream.chunk_every(@limit_page)
    |> Enum.at(page - 1)
  end

  def get_last_transaction(address) do
    case Archethic.get_last_transaction(address) do
      {:ok, tx} ->
        {:ok, Transaction.to_map(tx)}

      {:error, _} = e ->
        e
    end
  end

  def get_transaction(address) do
    case Archethic.search_transaction(address) do
      {:ok, tx} ->
        {:ok, Transaction.to_map(tx)}

      {:error, _} = e ->
        e
    end
  end

  def get_chain_length(address) do
    Archethic.get_transaction_chain_length(address)
  end

  def nodes do
    Enum.map(
      P2P.list_nodes(),
      &%{
        first_public_key: &1.first_public_key,
        last_public_key: &1.last_public_key,
        ip: :inet.ntoa(&1.ip),
        port: &1.port,
        geo_patch: &1.geo_patch,
        network_patch: &1.network_patch,
        reward_address: &1.reward_address,
        authorized: &1.authorized?,
        available: &1.available?,
        enrollment_date: &1.enrollment_date,
        authorization_date: &1.authorization_date,
        average_availability: &1.average_availability
      }
    )
  end

  def network_transactions(type, page) do
    TransactionChain.list_transactions_by_type(type, [])
    |> paginate_transactions(page)
  end
end
