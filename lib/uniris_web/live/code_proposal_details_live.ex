defmodule UnirisWeb.CodeProposalDetailsLive do
  @moduledoc false
  use Phoenix.LiveView

  alias Phoenix.View
  alias UnirisWeb.CodeView

  alias Uniris.Governance.ProposalMetadata

  alias Uniris.PubSub

  alias Uniris.Storage

  alias Uniris.Transaction
  alias Uniris.TransactionData

  def mount(_params, %{"address" => address}, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction()
      PubSub.register_to_code_proposal_deployment(address)
    end

    case Storage.get_transaction(Base.decode16!(address, case: :mixed)) do
      {:ok, tx} ->
        %{changes: changes, description: description, approvals: approvals} =
          extract_code_proposal(tx)

        new_socket =
          socket
          |> assign(:changes, changes)
          |> assign(:description, description)
          |> assign(:approvals, approvals)
          |> assign(:address, address)
          |> assign(:exists?, true)
          |> assign(:deployed?, false)

        {:ok, new_socket}

      {:error, :transaction_not_exists} ->
        new_socket =
          socket
          |> assign(:address, address)
          |> assign(:exists?, false)
          |> assign(:deployed?, false)

        {:ok, new_socket}
    end
  end

  def render(assigns) do
    View.render(CodeView, "proposal_details.html", assigns)
  end

  def handle_info(
        {:new_transaction, tx = %Transaction{type: :code_proposal}},
        socket = %{assigns: %{address: proposal_address}}
      ) do
    if Base.encode16(tx.address) == proposal_address do
      {:noreply, assign(socket, extract_code_proposal(tx))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:new_transaction, %Transaction{address: address, type: :code_approval}},
        socket
      ) do
    {:noreply, update(socket, :approvals, &[address | &1])}
  end

  def handle_info({:new_transaction, _}, socket) do
    {:noreply, socket}
  end

  def handle_info({:proposal_deployment, p2p_port, web_port}, socket) do
    new_socket =
      socket
      |> update(:deployed?, true)
      |> update(:p2p_port, p2p_port)
      |> update(:web_port, web_port)

    {:noreply, new_socket}
  end

  defp extract_code_proposal(%Transaction{
         address: address,
         type: :code_proposal,
         data: %TransactionData{content: content}
       }) do
    approvals = Storage.get_pending_transaction_signatures(address)

    %{
      address: Base.encode16(address),
      description: ProposalMetadata.get_description(content),
      changes: ProposalMetadata.get_changes(content),
      approvals: approvals,
      exists?: true
    }
  end
end
