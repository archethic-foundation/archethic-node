defmodule UnirisWeb.NodeLive do
  use Phoenix.LiveView

  alias UnirisCore.P2P

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :nodes, P2P.list_nodes() |> Enum.filter(& &1.ready?))}
  end

  def render(assigns) do
    ~L"""
    <div class="row">
      <div class="column column-20">Node public key</div>
      <div class="column column-10">IP</div>
      <div class="column column-10">Port</div>
      <div class="column column-10">Available</div>
      <div class="column column-20">Average availability</div>
      <div class="column column-10">Geo patch</div>
      <div class="column column-10">Authorized</div>
    </div>

    <%= for node <- @nodes do %>
    <div class="row">
      <div class="column column-20">
        <span style="text-overflow: ellipsis; white-space: nowrap; overflow: hidden; display: block;">
          <%= Base.encode16(node.last_public_key) %>
        </span>
      </div>
      <div class="column column-10"><%= :inet_parse.ntoa(node.ip) %></div>
      <div class="column column-10"><%= node.port %></div>
      <div class="column column-10"><%= node.availability == 1 %></div>
      <div class="column column-20"><%= node.average_availability %></div>
      <div class="column column-10"><%= node.geo_patch %></div>
      <div class="column column-10"><%= node.authorized? %></div>
    </div>
    <% end %>
    """
  end
end
