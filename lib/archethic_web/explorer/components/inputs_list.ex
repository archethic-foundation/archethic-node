defmodule ArchethicWeb.Explorer.Components.InputsList do
  @moduledoc false

  alias ArchethicWeb.ExplorerRouter.Helpers, as: Routes

  use Phoenix.Component
  use Phoenix.HTML

  import ArchethicWeb.WebUtils

  def display_all(assigns) do
    ~H"""
    <table class="table ae-table is-fullwidth is-hoverable">
      <thead>
        <tr>
          <th>Asset</th>
          <th>Amount</th>
          <th>From</th>
          <th>Date (UTC)</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
        <%= for input <- @inputs do %>
          <tr>
            <td>
              <%= case input.type do %>
                <% :UCO -> %>
                  <span class="tag is-gradient">UCO</span>
                  <%= if input.reward? do %>
                    <span class="tag is-gradient">MUCO</span>
                  <% end %>
                <% {:token, token_address, token_id} -> %>
                  <%= link to: Routes.live_path(@socket, ArchethicWeb.Explorer.TransactionDetailsLive, Base.encode16(token_address)) do %>
                    <span class="tag is-gradient">
                      <%= if token_id >= 1 do %>
                        Token #<%= token_id %>
                      <% else %>
                        <%= case Map.get(@token_properties, token_address, %{}) |> Map.get(:symbol) do %>
                          <% nil -> %>
                            <%= short_address(token_address) %>
                          <% symbol -> %>
                            <span class="mono"><%= symbol %></span>
                        <% end %>
                      <% end %>
                    </span>
                  <% end %>
              <% end %>
            </td>
            <td>
              <%= case input.type do
                {:token, token_address, _} ->
                  decimals =
                    Map.get(@token_properties, token_address, %{})
                    |> Map.get(:decimals, 8)

                  from_bigint(input.amount, decimals)

                _ ->
                  from_bigint(input.amount)
              end %>
            </td>

            <td>
              <%= link(short_address(input.from),
                to:
                  Routes.live_path(
                    @socket,
                    ArchethicWeb.Explorer.TransactionDetailsLive,
                    Base.encode16(input.from)
                  )
              ) %>
            </td>

            <td><%= format_date(input.timestamp, display_utc: false) %></td>
            <td>
              <%= if input.spent? do %>
                <span class="tag is-danger">Spent</span>
              <% else %>
                <span class="tag is-success">Unspent</span>
              <% end %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end
end
