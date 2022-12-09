defmodule ArchethicWeb.TransactionChainLive do
  @moduledoc false

  use ArchethicWeb, :live_view

  alias Archethic.Crypto
  alias Archethic.OracleChain
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

  @spec render(Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    View.render(ExplorerView, "chain.html", assigns)
  end

  defp get_paginated_transaction_chain(address) do
    with {:ok, addr} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(addr),
         {:ok, %Transaction{address: last_address}} <- Archethic.get_last_transaction(addr),
         {:ok, chain_length} <- Archethic.get_transaction_chain_length(last_address),
         # -------------

         # {:ok, chain} <- Archethic.get_transaction_chain(last_address),
         {:ok, chain} <- Archethic.get_transaction_chain_by_paging_address(last_address, addr),
         # -------------
         {:ok, %{uco: uco_balance}} <- Archethic.get_balance(addr),
         uco_price <- DateTime.utc_now() |> OracleChain.get_uco_price() do
      IO.inspect(chain_length, label: "chainlength")

      %{
        transaction_chain: List.flatten(chain),
        address: addr,
        chain_size: chain_length,
        uco_balance: uco_balance,
        uco_price: uco_price
      }
    else
      :error ->
        %{
          transaction_chain: [],
          address: "",
          chain_size: 0,
          uco_balance: 0,
          error: "Invalid address",
          uco_price: [eur: 0.05, usd: 0.07]
        }

      false ->
        %{
          transaction_chain: [],
          address: "",
          chain_size: 0,
          uco_balance: 0,
          error: "Invalid address",
          uco_price: [eur: 0.05, usd: 0.07]
        }

      {:error, :transaction_not_exists} ->
        %{
          transaction_chain: [],
          address: "",
          chain_size: 0,
          uco_balance: 0,
          error: "Transaction not found",
          uco_price: [eur: 0.05, usd: 0.07]
        }

      {:error, _} ->
        %{
          transaction_chain: [],
          address: "",
          chain_size: 0,
          uco_balance: 0,
          error: "Network issue",
          uco_price: [eur: 0.05, usd: 0.07]
        }
    end
  end
end
