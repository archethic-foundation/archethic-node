defmodule UnirisWeb.CodeProposalsLive do
  @moduledoc false
  use Phoenix.LiveView

  alias Phoenix.View

  alias Uniris.Governance

  alias Uniris.PubSub

  alias UnirisWeb.CodeView

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction_by_type(:code_proposal)
    end

    proposals = Governance.list_code_proposals()
    {:ok, assign(socket, :proposals, proposals)}
  end

  def render(assigns) do
    View.render(CodeView, "proposal_list.html", assigns)
  end

  def handle_info({:new_transaction, address, :code_proposal, _}, socket) do
    {:ok, prop} = Governance.get_code_proposal(address)
    {:noreply, update(socket, :proposals, &[prop | &1])}
  end
end
