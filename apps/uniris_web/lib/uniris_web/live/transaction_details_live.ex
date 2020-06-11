defmodule UnirisWeb.TransactionDetailsLive do
  use Phoenix.LiveView

  alias UnirisCore.Transaction
  alias UnirisCore.Crypto

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, %{exists: false, previous_address: nil, transaction: nil, hide_content: true})}
  end

  def handle_params(opts = %{"address" => address}, _uri, socket) do
    address = Base.decode16!(address)

    case Map.get(opts, "latest") do
      "true" ->
        UnirisCore.get_last_transaction(address)

      _ ->
        UnirisCore.search_transaction(address)
    end
    |> case do
      {:ok, tx = %Transaction{previous_public_key: previous_public_key}} ->
        balance = UnirisCore.get_balance(address)
        previous_address = Crypto.hash(previous_public_key)
        inputs = UnirisCore.get_transaction_inputs(previous_address)

        new_socket =
          socket
          |> assign(:transaction, tx)
          |> assign(:previous_address, previous_address)
          |> assign(:balance, balance)
          |> assign(:inputs, inputs)
          |> assign(:address, address)

        {:noreply, new_socket}

      _ ->
        inputs = UnirisCore.get_transaction_inputs(address)

        new_socket =
          socket
          |> assign(:address, address)
          |> assign(:inputs, inputs)

        {:noreply, new_socket}
    end
  end

  def handle_event("toggle_content", _value, socket = %{assigns: %{hide_content: false}}) do
    {:noreply, assign(socket, :hide_content, true)}
  end

  def handle_event("toggle_content", _value, socket = %{assigns: %{hide_content: true}}) do
    {:noreply, assign(socket, :hide_content, false)}
  end

  def render(assigns) do
    Phoenix.View.render(UnirisWeb.ExplorerView, "transaction_details.html", assigns)
  end
end
