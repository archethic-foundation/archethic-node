defmodule UnirisWeb.CodeProposalChatLive do
  @moduledoc false

  use Phoenix.LiveView

  alias Phoenix.View

  # alias Uniris.P2P
  # alias Uniris.P2P.Message.NewChatProposal
  # alias Uniris.PubSub

  # alias Uniris.TaskSupervisor

  alias UnirisWeb.CodeView
  alias UnirisWeb.Endpoint

  def mount(_, session, socket) do
    proposal_address = Map.get(session, "proposal")

    if connected?(socket) do
      # PubSub.register_to_proposal_message(proposal_address)
      Endpoint.subscribe(topic(proposal_address))
    end

    {:ok, assign(socket, proposal_address: proposal_address, chats: [])}
  end

  def render(assigns) do
    View.render(CodeView, "proposal_chat.html", assigns)
  end

  def handle_event(
        "new_message",
        %{"message" => message},
        socket = %{assigns: %{proposal_address: proposal_address}}
      ) do
    chat = %{
      message: message,
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
    {:noreply, update(socket, :chats, &(&1 ++ [chat]))}
  end

  def handle_info(%{event: "message", payload: chat}, socket) do
    {:noreply, update(socket, :chats, &(&1 ++ [chat]))}
  end

  def handle_info(
        {:new_proposal_message, message, timestamp},
        socket = %{assigns: %{proposal_address: proposal_address}}
      ) do
    chat = %{
      message: message,
      timestamp: timestamp
    }

    Endpoint.broadcast_from(self(), topic(proposal_address), "message", chat)
    {:noreply, update(socket, :chats, &(&1 ++ [chat]))}
  end

  defp topic(address) do
    "proposal_#{address}"
  end
end
