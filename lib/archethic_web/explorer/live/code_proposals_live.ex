defmodule ArchethicWeb.Explorer.CodeProposalsLive do
  @moduledoc false
  use ArchethicWeb.Explorer, :live_view

  alias Archethic.Governance
  alias Archethic.PubSub
  import ArchethicWeb.Explorer.CodeView

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction_by_type(:code_proposal)
    end

    proposals = Governance.list_code_proposals()
    {:ok, assign(socket, :proposals, proposals)}
  end

  def handle_info({:new_transaction, address, :code_proposal, _}, socket) do
    {:ok, prop} = Governance.get_code_proposal(address)
    {:noreply, update(socket, :proposals, &[prop | &1])}
  end
end
