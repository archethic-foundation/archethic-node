defmodule ArchethicWeb.TransactionDetailsLive do
  @moduledoc false
  use ArchethicWeb, :live_view

  alias Phoenix.View

  alias Archethic.Crypto

  alias Archethic.PubSub

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias ArchethicWeb.ExplorerView

  alias Archethic.OracleChain

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, %{
       exists: false,
       previous_address: nil,
       transaction: nil,
       inputs: [],
       calls: []
     })}
  end

  def handle_params(opts = %{"address" => address}, _uri, socket) do
    with {:ok, addr} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(addr) do
      case get_transaction(addr, opts) do
        {:ok, tx} ->
          {:noreply, handle_transaction(socket, tx)}

        {:error, :transaction_not_exists} ->
          PubSub.register_to_new_transaction_by_address(addr)
          {:noreply, handle_not_existing_transaction(socket, addr)}

        {:error, :transaction_invalid} ->
          {:noreply, handle_invalid_transaction(socket, addr)}
      end
    else
      _ ->
        {:noreply, handle_invalid_address(socket, address)}
    end
  end

  def handle_info({:new_transaction, address}, socket) do
    {:ok, tx} = get_transaction(address, %{})

    new_socket =
      socket
      |> assign(:ko?, false)
      |> handle_transaction(tx)

    {:noreply, new_socket}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  def render(assigns = %{ko?: true}) do
    View.render(ExplorerView, "ko_transaction.html", assigns)
  end

  def render(assigns) do
    View.render(ExplorerView, "transaction_details.html", assigns)
  end

  defp get_transaction(address, %{"address" => "true"}) do
    Archethic.get_last_transaction(address)
  end

  defp get_transaction(address, _opts = %{}) do
    Archethic.search_transaction(address)
  end

  defp handle_transaction(
         socket,
         tx = %Transaction{
           address: address,
           data: %TransactionData{
             ledger: %Ledger{token: %TokenLedger{transfers: token_transfers}}
           },
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{transaction_movements: transaction_movements}
           }
         }
       ) do
    previous_address = Transaction.previous_address(tx)

    inputs = Archethic.get_transaction_inputs(address)
    ledger_inputs = Enum.reject(inputs, &(&1.type == :call))
    contract_inputs = Enum.filter(inputs, &(&1.type == :call))
    uco_price_at_time = tx.validation_stamp.timestamp |> OracleChain.get_uco_price()
    uco_price_now = DateTime.utc_now() |> OracleChain.get_uco_price()

    token_properties =
      get_token_addresses([], ledger_inputs)
      |> get_token_addresses(transaction_movements)
      |> get_token_addresses(token_transfers)
      |> Enum.uniq()
      |> get_token_properties()

    socket
    |> assign(:transaction, tx)
    |> assign(:previous_address, previous_address)
    |> assign(:inputs, ledger_inputs)
    |> assign(:calls, contract_inputs)
    |> assign(:address, address)
    |> assign(:uco_price_at_time, uco_price_at_time)
    |> assign(:uco_price_now, uco_price_now)
    |> assign(:token_properties, token_properties)
  end

  defp get_token_addresses(acc, [%TransactionMovement{type: {:token, token_address, _}} | rest]) do
    get_token_addresses([token_address | acc], rest)
  end

  defp get_token_addresses(acc, [%TransactionInput{type: {:token, token_address, _}} | rest]) do
    get_token_addresses([token_address | acc], rest)
  end

  defp get_token_addresses(acc, [%TokenTransfer{token_address: token_address} | rest]) do
    get_token_addresses([token_address | acc], rest)
  end

  defp get_token_addresses(acc, [_ | rest]) do
    get_token_addresses(acc, rest)
  end

  defp get_token_addresses(acc, []), do: acc

  defp get_token_properties(token_addresses) do
    Task.async_stream(token_addresses, fn token_address ->
      case Archethic.search_transaction(token_address) do
        {:ok, %Transaction{data: %TransactionData{content: content}, type: :token}} ->
          {token_address, content}

        _ ->
          :error
      end
    end)
    |> Enum.reduce(%{}, fn
      {:ok, {token_address, content}}, acc ->
        case Jason.decode(content) do
          {:ok, map} ->
            properties = %{
              decimals: Map.get(map, "decimals", 8),
              symbol: Map.get(map, "symbol")
            }

            Map.put(acc, token_address, properties)

          _ ->
            acc
        end

      _, acc ->
        acc
    end)
  end

  defp handle_not_existing_transaction(socket, address) do
    inputs = Archethic.get_transaction_inputs(address)
    ledger_inputs = Enum.reject(inputs, &(&1.type == :call))
    contract_inputs = Enum.filter(inputs, &(&1.type == :call))

    socket
    |> assign(:address, address)
    |> assign(:inputs, ledger_inputs)
    |> assign(:calls, contract_inputs)
    |> assign(:error, :not_exists)
  end

  defp handle_invalid_address(socket, address) do
    socket
    |> assign(:address, address)
    |> assign(:error, :invalid_address)
  end

  defp handle_invalid_transaction(socket, address) do
    socket
    |> assign(:address, address)
    |> assign(:ko?, true)
  end
end
