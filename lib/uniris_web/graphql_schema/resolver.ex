defmodule UnirisWeb.GraphQLSchema.Resolver do
  @moduledoc false

  alias Uniris

  alias Uniris.Crypto

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionInput

  @limit_page 10

  def get_balance(address) do
    %{uco: uco, nft: nft_balances} = Uniris.get_balance(address)

    %{
      uco: uco,
      nft:
        nft_balances
        |> Enum.map(fn {address, amount} -> %{address: address, amount: amount} end)
        |> Enum.sort_by(& &1.amount)
    }
  end

  def get_inputs(address) do
    inputs = Uniris.get_transaction_inputs(address)
    Enum.map(inputs, &TransactionInput.to_map/1)
  end

  def shared_secrets do
    %{
      storage_nonce_public_key: Crypto.storage_nonce_public_key()
    }
  end

  def paginate_chain(address, page) do
    address
    |> Uniris.get_transaction_chain()
    |> paginate_transactions(page)
  end

  def paginate_local_transactions(page) do
    paginate_transactions(TransactionChain.list_all(), page)
  end

  defp paginate_transactions(transactions, page) do
    start_pagination = (page - 1) * @limit_page
    end_pagination = @limit_page

    transactions
    |> Enum.slice(start_pagination, end_pagination)
    |> Enum.map(&Transaction.to_map/1)
  end

  def get_last_transaction(address) do
    case Uniris.get_last_transaction(address) do
      {:ok, tx} ->
        {:ok, Transaction.to_map(tx)}

      {:error, :transaction_not_exists} = e ->
        e
    end
  end

  def get_transaction(address) do
    case Uniris.search_transaction(address) do
      {:ok, tx} ->
        {:ok, Transaction.to_map(tx)}

      {:error, :transaction_not_exists} = e ->
        e
    end
  end

  def get_chain_length(address) do
    Uniris.get_transaction_chain_length(address)
  end
end
