defmodule UnirisWeb.CodeProposalDetailsLive do
  @moduledoc false
  use UnirisWeb, :live_view

  alias Phoenix.View
  alias UnirisWeb.CodeView

  alias Uniris.Governance
  alias Uniris.Governance.Code.Proposal

  alias Uniris.PubSub

  def mount(%{"address" => address}, _params, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction_by_address(address)
      PubSub.register_to_code_proposal_deployment(address)
    end

    case Base.decode16(address, case: :mixed) do
      {:ok, addr} ->
        case Governance.get_code_proposal(addr) do
          {:ok, prop} ->
            new_socket =
              socket
              |> assign(:proposal, prop)
              |> assign(:exists?, true)
              |> assign(:address, addr)
              |> assign(:deployed?, false)

            {:ok, new_socket}

          _ ->
            new_socket =
              socket
              |> assign(:address, addr)
              |> assign(:deployed?, false)
              |> assign(:exists?, false)

            {:ok, new_socket}
        end

      _ ->
        {:ok, assign(socket, :error, :invalid_address)}
    end
  end

  def render(assigns) do
    View.render(CodeView, "proposal_details.html", assigns)
  end

  def handle_info(
        {:new_transaction, address, :code_proposal, _timestamp},
        socket = %{assigns: %{address: proposal_address}}
      ) do
    if Base.encode16(address) == proposal_address do
      {:ok, prop} = Governance.get_code_proposal(address)
      {:noreply, assign(socket, :proposal, prop)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:new_transaction, address, :code_approval, _timestamp},
        socket
      ) do
    new_socket = update(socket, :proposal, &Proposal.add_approval(&1, address))
    {:noreply, new_socket}
  end

  def handle_info({:new_transaction, _, _, _}, socket) do
    {:noreply, socket}
  end

  def handle_info({:proposal_deployment, p2p_port, web_port}, socket) do
    new_socket =
      socket
      |> assign(:deployed?, true)
      |> assign(:p2p_port, p2p_port)
      |> assign(:web_port, web_port)

    {:noreply, new_socket}
  end
end
