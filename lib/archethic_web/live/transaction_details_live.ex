defmodule ArchEthicWeb.TransactionDetailsLive do
  @moduledoc false
  use ArchEthicWeb, :live_view

  alias Phoenix.View

  alias ArchEthic.Crypto

  alias ArchEthic.PubSub

  alias ArchEthic.TransactionChain.Transaction

  alias ArchEthicWeb.ExplorerView

  alias ArchEthic.OracleChain

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, %{
       exists: false,
       previous_address: nil,
       transaction: nil
     })}
  end

  def handle_params(opts = %{"address" => address}, _uri, socket) do
    with {:ok, addr} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_hash?(addr),
         {:ok, tx} <- get_transaction(addr, opts) do
      {:noreply, handle_transaction(socket, tx)}
    else
      {:error, :transaction_not_exists} ->
        PubSub.register_to_new_transaction_by_address(Base.decode16!(address, case: :mixed))
        {:noreply, handle_not_existing_transaction(socket, Base.decode16!(address, case: :mixed))}

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
    ArchEthic.get_last_transaction(address)
  end

  defp get_transaction(address, _opts = %{}) do
    ArchEthic.search_transaction(address)
  end

  defp handle_transaction(
         socket,
         tx = %Transaction{address: address}
       ) do
    previous_address = Transaction.previous_address(tx)

    with {:ok, balance} <- ArchEthic.get_balance(address),
         {:ok, inputs} <- ArchEthic.get_transaction_inputs(address) do
      ledger_inputs = Enum.reject(inputs, &(&1.type == :call))
      contract_inputs = Enum.filter(inputs, &(&1.type == :call))
      uco_price_at_time = tx.validation_stamp.timestamp |> OracleChain.get_uco_price()
      uco_price_now = DateTime.utc_now() |> OracleChain.get_uco_price()

      socket
      |> assign(:transaction, tx)
      |> assign(:previous_address, previous_address)
      |> assign(:balance, balance)
      |> assign(:inputs, ledger_inputs)
      |> assign(:calls, contract_inputs)
      |> assign(:address, address)
      |> assign(:uco_price_at_time, uco_price_at_time)
      |> assign(:uco_price_now, uco_price_now)
    else
      {:error, :network_issue} ->
        socket
        |> assign(:error, :network_issue)
        |> assign(:address, address)
        |> assign(:inputs, [])
        |> assign(:calls, [])
    end
  end

  def handle_not_existing_transaction(socket, address) do
    case ArchEthic.get_transaction_inputs(address) do
      {:ok, inputs} ->
        ledger_inputs = Enum.reject(inputs, &(&1.type == :call))
        contract_inputs = Enum.filter(inputs, &(&1.type == :call))

        socket
        |> assign(:address, address)
        |> assign(:inputs, ledger_inputs)
        |> assign(:calls, contract_inputs)
        |> assign(:error, :not_exists)

      {:error, :network_issue} ->
        socket
        |> assign(:address, address)
        |> assign(:inputs, [])
        |> assign(:calls, [])
        |> assign(:error, :network_issue)
    end
  end

  def handle_invalid_address(socket, address) do
    socket
    |> assign(:address, address)
    |> assign(:inputs, [])
    |> assign(:calls, [])
    |> assign(:error, :invalid_address)
  end
end
