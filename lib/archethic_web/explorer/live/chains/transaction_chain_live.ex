defmodule ArchethicWeb.Explorer.TransactionChainLive do
  @moduledoc """
  Displays the transaction chain (all transactions in the chain) of an address.
  User can type any address part of the chain. We will always fetch from the latest transaction DESC.
  There is an infinite scrolling. 10 transactions are loaded at a time.
  """

  use ArchethicWeb.Explorer, :live_view

  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias Archethic.UTXO
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchethicWeb.Explorer.Components.TransactionsList
  alias ArchethicWeb.Explorer.Components.UnspentOutputList
  alias ArchethicWeb.Explorer.Components.Amount
  alias ArchethicWeb.WebUtils

  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(params, _session, socket) do
    if connected?(socket) do
      encoded_address = params["address"]

      state =
        case encoded_address do
          nil ->
            %{}

          _ ->
            with {:ok, address} <- decode_address(encoded_address),
                 {chain_size, chain_txs, genesis_address} <- fetch_data(address),
                 chain_utxos <- Archethic.get_unspent_outputs(genesis_address),
                 balance <- get_balance(chain_utxos) do
              # asynchronously fetch the token properties
              Task.async(fn -> fetch_token_properties(chain_utxos) end)

              %{
                address: address,
                genesis_address: genesis_address,
                page: 1,
                paging_address: unless(Enum.empty?(chain_txs), do: List.last(chain_txs).address),
                chain_utxos: chain_utxos,
                chain_txs: chain_txs,
                chain_size: chain_size,
                balance: balance,
                uco_price_now: OracleChain.get_uco_price(DateTime.utc_now()),
                token_properties: %{}
              }
            else
              {:error, :invalid_address} -> %{error: "Invalid address"}
              {:error, :network_issue} -> %{error: "Network issue"}
            end
        end

      {:ok, assign(socket, state)}
    else
      # do not refetch data when socket connect
      {:ok, socket}
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
            page: page,
            paging_address: paging_address,
            chain_txs: chain_txs,
            chain_size: size
          }
        }
      ) do
    with false <- length(chain_txs) == size,
         {:ok, next_transactions} <-
           Archethic.get_pagined_transaction_chain(paging_address, paging_address, :desc) do
      {:noreply,
       assign(socket, %{
         page: page + 1,
         chain_txs: chain_txs ++ next_transactions,
         paging_address: List.last(next_transactions).address
       })}
    else
      _error ->
        {:noreply, socket}
    end
  end

  # Task.async result
  def handle_info({_ref, {:token_properties, token_properties}}, socket) do
    {:noreply, assign(socket, :token_properties, token_properties)}
  end

  # Task.async down
  def handle_info({:DOWN, _ref, :process, _pid, :normal}, socket) do
    {:noreply, socket}
  end

  defp decode_address(encoded_address) do
    with {:ok, addr} <- Base.decode16(encoded_address, case: :mixed),
         true <- Crypto.valid_address?(addr) do
      {:ok, addr}
    else
      _ ->
        {:error, :invalid_address}
    end
  end

  defp fetch_data(address) do
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
  rescue
    _ -> {:error, :network_issue}
  end

  defp fetch_token_properties(utxos) do
    {:token_properties,
     Enum.reduce(utxos, [], fn
       %UnspentOutput{type: {:token, token_address, _token_id}}, acc -> [token_address | acc]
       _, acc -> acc
     end)
     |> Enum.uniq()
     |> WebUtils.get_token_properties()}
  end

  defp get_balance(utxos) do
    %{uco: uco, token: tokens} = UTXO.get_balance(utxos)

    Enum.reduce(tokens, %{:UCO => uco}, fn
      {{token_address, token_id}, amount}, acc ->
        Map.put(acc, {:token, token_address, token_id}, amount)
    end)
  end
end
