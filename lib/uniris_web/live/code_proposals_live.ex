defmodule UnirisWeb.CodeProposalsLive do
  @moduledoc false
  use Phoenix.LiveView

  alias Phoenix.View

  alias Uniris.Governance.Proposal

  alias Uniris.Transaction
  alias Uniris.TransactionData

  # alias Uniris.PubSub
  alias UnirisWeb.CodeView

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # PubSub.register_to_node_update()
    end

    {:ok, assign(socket, :proposals, [])}
  end

  def render(assigns) do
    View.render(CodeView, "proposal_list.html", assigns)
  end

  def handle_info({:new_transaction, tx = %Transaction{type: :code_proposal}}, socket) do
    {:noreply, update(socket, :proposals, &[extract_code_proposal(tx) | &1])}
  end

  def handle_info({:new_transaction, _}, socket) do
    {:noreply, socket}
  end

  defp extract_code_proposal(%Transaction{
         address: address,
         timestamp: timestamp,
         data: %TransactionData{content: content},
         previous_public_key: previous_public_key
       }) do
    # approvals = Storage.get_pending_transaction_signatures(address)
    nb_approvals = 0

    %{
      address: address,
      timestamp: timestamp,
      previous_public_key: previous_public_key,
      description: Proposal.get_description(content),
      nb_approvals: nb_approvals
    }
  end
end
