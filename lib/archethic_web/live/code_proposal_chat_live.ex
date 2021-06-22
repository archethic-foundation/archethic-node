defmodule ArchEthicWeb.CodeProposalChatLive do
  @moduledoc false
  use ArchEthicWeb, :live_view

  # alias ArchEthic.P2P
  # alias ArchEthic.P2P.Message.NewChatProposal
  # alias ArchEthic.PubSub

  # alias ArchEthic.TaskSupervisor

  alias Phoenix.View

  alias ArchEthicWeb.CodeView
  alias ArchEthicWeb.Endpoint

  def mount(_params, %{"proposal_address" => proposal_address}, socket) do
    if connected?(socket) do
      # PubSub.register_to_proposal_message(proposal_address)
      Endpoint.subscribe(topic(proposal_address))
    end

    new_socket =
      socket
      |> assign(:chats, [])
      |> assign(:proposal_address, proposal_address)

    {:ok, new_socket}
  end

  def render(assigns) do
    View.render(CodeView, "proposal_chat.html", assigns)
  end

  def handle_event(
        "new_message",
        %{"comment" => comment, "name" => name},
        socket = %{assigns: %{proposal_address: proposal_address}}
      ) do
    chat = %{
      comment: comment,
      name: name,
      timestamp: DateTime.utc_now()
    }

    # msg = %NewChatProposal{
    #   proposal: proposal_address,
    #   timestamp: chat.timestamp,
    #   message: message
    # }

    # P2P.list_nodes()
    # |> Task.Supervisor.async_stream_nolink(TaskSupervisor, &P2P.send_message(&1, msg))
    # |> Stream.run()

    Endpoint.broadcast_from(self(), topic(proposal_address), "message", chat)
    {:noreply, update(socket, :chats, &[chat | &1])}
  end

  def handle_info(%{event: "message", payload: chat}, socket) do
    {:noreply, update(socket, :chats, &[chat | &1])}
  end

  def handle_info(
        {:new_proposal_message, comment, name, timestamp},
        socket = %{assigns: %{proposal_address: proposal_address}}
      ) do
    chat = %{
      comment: comment,
      name: name,
      timestamp: timestamp
    }

    Endpoint.broadcast_from(self(), topic(proposal_address), "message", chat)
    {:noreply, update(socket, :chats, &[chat | &1])}
  end

  defp topic(address) do
    "proposal_#{address}"
  end
end
