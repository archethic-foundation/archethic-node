defmodule UnirisWeb.NodeLive do
  use Phoenix.LiveView

  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.PubSub

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_node_update()
    end
    {:ok, assign(socket, :nodes, P2P.list_nodes() |> Enum.filter(& &1.ready?))}
  end

  def render(assigns) do
    ~L"""
    <div class="row" style="justify-content: space-between">
      <div class="column column-20">Node public key</div>
      <div class="column column-10">IP</div>
      <div class="column column-10">Port</div>
      <div class="column column-10">Available</div>
      <div class="column column-10">Average availability</div>
      <div class="column column-10">Geo patch</div>
      <div class="column column-10">Authorized</div>
      <div class="column column-10">Enrollment date</div>
    </div>

    <%= for node <- @nodes do %>
    <div class="row" style="justify-content: space-between">
      <div class="column column-20">
        <span style="text-overflow: ellipsis; white-space: nowrap; overflow: hidden; display: block;">
          <%= Base.encode16(node.last_public_key) %>
        </span>
      </div>
      <div class="column column-10"><%= :inet_parse.ntoa(node.ip) %></div>
      <div class="column column-10"><%= node.port %></div>
      <div class="column column-10"><%= node.available? %></div>
      <div class="column column-10"><%= node.average_availability %></div>
      <div class="column column-10"><%= node.geo_patch %></div>
      <div class="column column-10"><%= node.authorized? %></div>
      <div class="column column-10"><%= :io_lib.format("~4..0B/~2..0B/~2..0B", [node.enrollment_date.year, node.enrollment_date.month, node.enrollment_date.day]) %></div>
    </div>
    <% end %>
    """
  end

  def handle_info({:node_update, node = %Node{}}, socket) do
    new_socket = update(socket, :nodes, fn nodes ->
      Enum.uniq_by([node | nodes], & &1.first_public_key)
    end)
    {:noreply, new_socket}
  end
end
