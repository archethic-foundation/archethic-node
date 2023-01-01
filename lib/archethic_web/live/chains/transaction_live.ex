defmodule ArchethicWeb.TransactionChainLive do
  @moduledoc """
  Displays the transaction chain (all transactions in the chain) of an address.
  User can type any address part of the chain. We will always fetch from the latest transaction DESC.
  There is an infinite scrolling. 10 transactions are loaded at a time.

  ps: We do not actually use the `page` assign, we need it for the InfiniteScroll hook to work.
      We use instead the address of the last transaction loaded for the pagination.
  """

  use ArchethicWeb, :live_view

  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

  alias ArchethicWeb.{ExplorerView}

  alias Phoenix.{View}

  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(params, _session, socket) do
    case params["address"] do
      nil ->
        {:ok,
         assign(socket, %{
           page: 1,
           transaction_chain: [],
           address: "",
           last_address: "",
           chain_size: 0,
           uco_balance: 0,
           uco_price: [eur: 0.05, usd: 0.07]
         })}

      address ->
        {:ok, assign(socket, get_paginated_transaction_chain(address))}
    end
  end

  @spec render(Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    View.render(ExplorerView, "chain.html", assigns)
  end

  @doc """
  Event called by the infinite scrolling to load more transactions
  """
  def handle_event("load-more", _, socket) do
    %{
      transaction_chain: transaction_chain,
      last_address: last_address,
      chain_size: size,
      page: page
    } = socket.assigns

    with false <- length(transaction_chain) == size,
         %Transaction{address: paging_address} <- List.last(transaction_chain),
         {:ok, last_address} <- Base.decode16(last_address, case: :mixed),
         {:ok, next_transactions} <- paginate_chain(last_address, paging_address) do
      {:noreply,
       assign(socket, %{
         page: page + 1,
         transaction_chain: transaction_chain ++ next_transactions
       })}
    else
      _error ->
        {:noreply, socket}
    end
  end

  defp get_paginated_transaction_chain(encoded_address) do
    with {:ok, addr} <- Base.decode16(encoded_address, case: :mixed),
         true <- Crypto.valid_address?(addr),
         {:ok, %Transaction{address: last_address}} <- Archethic.get_last_transaction(addr),
         {:ok, chain_length} <- Archethic.get_transaction_chain_length(last_address),
         {:ok, chain} <- paginate_chain(last_address, nil),
         {:ok, %{uco: uco_balance}} <- Archethic.get_balance(last_address),
         uco_price <- DateTime.utc_now() |> OracleChain.get_uco_price() do
      %{
        page: 1,
        transaction_chain: List.flatten(chain),
        address: encoded_address,
        last_address: Base.encode16(last_address),
        chain_size: chain_length,
        uco_balance: uco_balance,
        uco_price: uco_price
      }
    else
      :error ->
        %{
          page: 1,
          transaction_chain: [],
          address: encoded_address,
          last_address: "",
          chain_size: 0,
          uco_balance: 0,
          error: "Invalid address",
          uco_price: [eur: 0.05, usd: 0.07]
        }

      false ->
        %{
          page: 1,
          transaction_chain: [],
          address: encoded_address,
          last_address: "",
          chain_size: 0,
          uco_balance: 0,
          error: "Invalid address",
          uco_price: [eur: 0.05, usd: 0.07]
        }

      {:error, :transaction_not_exists} ->
        # no error here, because there's a message for this case in the template
        %{
          page: 1,
          transaction_chain: [],
          address: encoded_address,
          last_address: "",
          chain_size: 0,
          uco_balance: 0,
          uco_price: [eur: 0.05, usd: 0.07]
        }

      {:error, _} ->
        %{
          page: 1,
          transaction_chain: [],
          address: encoded_address,
          last_address: "",
          chain_size: 0,
          uco_balance: 0,
          error: "Network issue",
          uco_price: [eur: 0.05, usd: 0.07]
        }
    end
  end

  # DESC pagination
  defp paginate_chain(address, paging_address) do
    nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())
    TransactionChain.fetch_transaction_chain(nodes, address, paging_address, order: :desc)
  end
end
