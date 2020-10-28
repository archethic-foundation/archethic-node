defmodule UnirisWeb.CodeProposalDetailsLive do
  @moduledoc false
  use Phoenix.LiveView

  alias Phoenix.View
  alias UnirisWeb.CodeView

  alias Uniris.Governance
  alias Uniris.Governance.Code.Proposal

  alias Uniris.PubSub

  def mount(_params, %{"address" => address}, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction_by_address(address)
      PubSub.register_to_code_proposal_deployment(address)
    end

    bin_address = Base.decode16!(address, case: :mixed)
    logs = Governance.list_code_proposal_integration_logs(bin_address)

    case Governance.get_code_proposal(bin_address) do
      {:ok, prop = %Proposal{}} ->
        new_socket =
          socket
          |> assign(:proposal, prop)
          |> assign(:address, address)
          |> assign(:exists?, true)
          |> assign(:deployed?, false)
          |> assign(:logs, logs)
          |> assign(:hide_logs, true)

        {:ok, new_socket}

      _ ->
        new_socket =
          socket
          |> assign(:address, address)
          |> assign(:exists?, false)
          |> assign(:deployed?, false)
          |> assign(:logs, logs)
          |> assign(:hide_logs, false)

        {:ok, new_socket}
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

      new_socket =
        socket
        |> assign(:proposal, prop)
        |> assign(:hide_logs, true)

      {:noreply, new_socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:new_transaction, address, :code_approval, _timestamp},
        socket
      ) do
    new_socket =
      socket
      |> update(:proposal, &Proposal.add_approval(&1, address))
      |> assign(:hide_logs, false)

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

  def handle_event("toggle_logs", _value, socket = %{assigns: %{hide_logs: false}}) do
    {:noreply, assign(socket, :hide_logs, true)}
  end

  def handle_event("toggle_logs", _value, socket = %{assigns: %{hide_logs: true}}) do
    {:noreply, assign(socket, :hide_logs, false)}
  end
end
