defmodule ArchethicWeb.GraphQLSchema.Resolver do
  @moduledoc false

  alias Archethic

  alias Archethic.Crypto

  alias Archethic.P2P

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionInput

  require Logger

  @limit_page 10

  def get_balance(address) do
    case Archethic.get_balance(address) do
      {:ok, %{uco: uco, token: token_balances}} ->
        balance = %{
          uco: uco,
          token:
            token_balances
            |> Enum.map(fn {{address, token_id}, amount} ->
              %{address: address, amount: amount, token_id: token_id}
            end)
            |> Enum.sort_by(& &1.amount)
        }

        {:ok, balance}

      {:error, :network_issue} = e ->
        e
    end
  end

  def get_token(address) do
    t1 = Task.async(fn -> TransactionChain.fetch_genesis_address_remotely(address) end)
    t2 = Task.async(fn -> get_transaction_content(address) end)

    with {:ok, {:ok, genesis_address}} <- Task.yield(t1),
         {:ok,
          {:ok,
           %{
             "name" => name,
             "supply" => supply,
             "symbol" => symbol,
             "type" => type,
             "properties" => properties
           }}} <- Task.yield(t2) do
      data_to_digest =
        case type do
          "fungible" ->
            %{genesis_address: Base.encode16(genesis_address), name: name, symbol: symbol}

          "non-fungible" ->
            %{
              genesis_address: Base.encode16(genesis_address),
              name: name,
              symbol: symbol,
              properties: properties
            }
        end

      token_id = :crypto.hash(:sha256, Jason.encode!(data_to_digest)) |> Base.encode16()

      {:ok,
       %{
         genesis: genesis_address,
         name: name,
         supply: supply,
         symbol: symbol,
         type: type,
         properties: do_reduce_properties(properties),
         id: token_id
       }}
    else
      {:ok, {:error, :network_issue}} ->
        {:error, "Network issue"}

      {:ok, {:error, :decode_error}} ->
        {:error, "Error in decoding transaction"}

      {:ok, {:error, :transaction_not_found}} ->
        {:error, "Transaction does not exist!"}

      {:exit, reason} ->
        Logger.debug("Task exited with reason")
        Logger.debug(reason)
        {:error, "Task Exited!"}

      nil ->
        {:error, "Task didn't responded within timeout!"}
    end
  end

  defp get_transaction_content(address) do
    case Archethic.search_transaction(address) do
      {:ok, %Transaction{data: %TransactionData{content: content}, type: :token}} ->
        case Jason.decode(content) do
          {:ok, map} -> {:ok, map}
          _ -> {:error, :decode_error}
        end

      _ ->
        {:error, :transaction_not_found}
    end
  end

  defp do_reduce_properties(property_list) do
    Enum.map(property_list, fn properties ->
      Enum.map(properties, fn %{"name" => n, "value" => v} ->
        %{name: n, value: v}
      end)
    end)
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

  def transaction_chain_by_paging_address(address, paging_address) do
    case Archethic.get_transaction_chain_by_paging_address(address, paging_address) do
      {:ok, chain} ->
        {:ok, chain}

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
        average_availability: &1.average_availability,
        origin_public_key: &1.origin_public_key
      }
    )
  end

  def network_transactions(type, page) do
    TransactionChain.list_transactions_by_type(type, [])
    |> paginate_transactions(page)
  end
end
