defmodule ArchethicWeb.Explorer.TransactionChainLive do
  @moduledoc """
  Displays the transaction chain (all transactions in the chain) of an address.
  User can type any address part of the chain. We will always fetch from the latest transaction DESC.
  There is an infinite scrolling. 10 transactions are loaded at a time.

  ps: We do not actually use the `page` assign, we need it for the InfiniteScroll hook to work.
      We use instead the address of the last transaction loaded for the pagination.
  """

  use ArchethicWeb.Explorer, :live_view

  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias ArchethicWeb.Explorer.Components.TransactionsList

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
           chain_size: 0,
           uco_balance: 0,
           uco_price: [eur: 0.05, usd: 0.07]
         })}

      address ->
        {:ok, assign(socket, get_paginated_transaction_chain(address))}
    end
  end

  @doc """
  Event called by the infinite scrolling to load more transactions
  """
  def handle_event(
        "load-more",
        _,
        socket = %{
          assigns: %{
            transaction_chain: transaction_chain,
            paging_address: paging_address,
            chain_size: size,
            page: page
          }
        }
      ) do
    with false <- length(transaction_chain) == size,
         {:ok, next_transactions} <-
           Archethic.get_pagined_transaction_chain(paging_address, paging_address, :desc) do
      {:noreply,
       assign(socket, %{
         page: page + 1,
         transaction_chain: transaction_chain ++ next_transactions,
         paging_address: List.last(next_transactions).address
       })}
    else
      _error ->
        {:noreply, socket}
    end
  end

  defp get_paginated_transaction_chain(encoded_address) do
    with {:ok, addr} <- Base.decode16(encoded_address, case: :mixed),
         true <- Crypto.valid_address?(addr),
         {chain_length, transactions, genesis_address} <- get_chain_data(addr),
         {:ok, %{uco: uco_balance}} <- Archethic.get_balance(genesis_address),
         uco_price <- DateTime.utc_now() |> OracleChain.get_uco_price() do
      paging_address = unless Enum.empty?(transactions), do: List.last(transactions).address

      %{
        page: 1,
        transaction_chain: transactions,
        address: encoded_address,
        paging_address: paging_address,
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
          chain_size: 0,
          uco_balance: 0,
          uco_price: [eur: 0.05, usd: 0.07]
        }

      {:error, _} ->
        %{
          page: 1,
          transaction_chain: [],
          address: encoded_address,
          chain_size: 0,
          uco_balance: 0,
          error: "Network issue",
          uco_price: [eur: 0.05, usd: 0.07]
        }
    end
  end

  defp get_chain_data(address) do
    [
      Task.async(fn -> Archethic.get_transaction_chain_length(address) end),
      Task.async(fn -> Archethic.get_pagined_transaction_chain(address, nil, :desc) end),
      Task.async(fn -> Archethic.fetch_genesis_address(address) end)
    ]
    |> Task.await_many(30_000)
    |> then(fn res ->
      if Enum.all?(res, &match?({:ok, _}, &1)),
        do: res |> Enum.map(&elem(&1, 1)) |> List.to_tuple(),
        else: {:error, :network_issue}
    end)
  end
end
