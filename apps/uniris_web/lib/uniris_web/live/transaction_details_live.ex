defmodule UnirisWeb.TransactionDetailsLive do
  use Phoenix.LiveView

  alias UnirisCore.Transaction
  alias UnirisCore.Storage
  alias UnirisCore.PubSub
  alias UnirisCore.Crypto

  def mount(_params, _session, socket) do
    {:ok, assign(socket, %{ exists: false, previous_address: nil, transaction: nil, hide_content: true})}
  end

  def handle_params(%{ "address" => address}, _uri, socket) do
    case address
    |> Base.decode16!()
    |> Storage.get_transaction() do
      {:ok, tx = %Transaction{previous_public_key: previous_public_key}} ->
        previous_address = Crypto.hash(previous_public_key)
        new_socket = socket
        |> assign(:transaction, tx)
        |> assign(:previous_address, previous_address)
        |> assign(:exists, true)
        {:noreply, new_socket}
      _ ->
        {:noreply, assign(socket, exists: false)}
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
