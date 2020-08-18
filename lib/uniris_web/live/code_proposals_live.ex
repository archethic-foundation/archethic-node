defmodule UnirisWeb.CodeProposalsLive do
  @moduledoc false
  use Phoenix.LiveView

  alias Phoenix.View

  alias Uniris.Governance.ProposalMetadata

  alias Uniris.Transaction
  alias Uniris.TransactionData

  alias Uniris.PubSub
  alias Uniris.Storage

  alias UnirisWeb.CodeView

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_code_proposal()
    end

    proposals = Storage.list_code_proposals() |> Enum.map(&extract_code_proposal/1)

    {:ok, assign(socket, :proposals, proposals)}
  end

  def render(assigns) do
    View.render(CodeView, "proposal_list.html", assigns)
  end

  def handle_info({:new_code_proposal, tx = %Transaction{type: :code_proposal}}, socket) do
    {:noreply, update(socket, :proposals, &[extract_code_proposal(tx) | &1])}
  end

  defp extract_code_proposal(%Transaction{
         address: address,
         timestamp: timestamp,
         data: %TransactionData{content: content},
         previous_public_key: previous_public_key
       }) do
    approvals = Storage.get_pending_transaction_signatures(address)
    nb_approvals = length(approvals)

    %{
      address: address,
      timestamp: timestamp,
      previous_public_key: previous_public_key,
      description: ProposalMetadata.get_description(content),
      nb_approvals: nb_approvals
    }
  end
end
