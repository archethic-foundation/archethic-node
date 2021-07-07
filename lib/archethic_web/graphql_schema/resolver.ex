defmodule ArchEthicWeb.GraphQLSchema.Resolver do
  @moduledoc false

  alias ArchEthic

  alias ArchEthic.Crypto

  alias ArchEthic.P2P

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionInput

  @limit_page 10

  def get_balance(address) do
    %{uco: uco, nft: nft_balances} = ArchEthic.get_balance(address)

    %{
      uco: uco,
      nft:
        nft_balances
        |> Enum.map(fn {address, amount} -> %{address: address, amount: amount} end)
        |> Enum.sort_by(& &1.amount)
    }
  end

  def get_inputs(address) do
    inputs = ArchEthic.get_transaction_inputs(address)
    Enum.map(inputs, &TransactionInput.to_map/1)
  end

  def shared_secrets do
    %{
      storage_nonce_public_key: Crypto.storage_nonce_public_key()
    }
  end

  def paginate_chain(address, page) do
    address
    |> ArchEthic.get_transaction_chain()
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
    case ArchEthic.get_last_transaction(address) do
      {:ok, tx} ->
        {:ok, Transaction.to_map(tx)}

      {:error, :transaction_not_exists} = e ->
        e
    end
  end

  def get_transaction(address) do
    case ArchEthic.search_transaction(address) do
      {:ok, tx} ->
        {:ok, Transaction.to_map(tx)}

      {:error, :transaction_not_exists} = e ->
        e
    end
  end

  def get_chain_length(address) do
    ArchEthic.get_transaction_chain_length(address)
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
end
