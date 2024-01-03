defmodule ArchethicWeb.Explorer.Components.InputsList do
  @moduledoc false

  alias ArchethicWeb.ExplorerRouter.Helpers, as: Routes

  use Phoenix.Component
  use Phoenix.HTML

  alias ArchethicWeb.Explorer.Components.Amount

  import ArchethicWeb.WebUtils

  def display_all(assigns) do
    # uco_price_at_time is optional because sometimes we do not have the time context
    # example: on a genesis page, there is no time
    assigns = assign(assigns, :uco_price_at_time, Map.get(assigns, :uco_price_at_time))

    ~H"""
    <table class="table ae-table is-fullwidth is-hoverable">
      <thead>
        <tr>
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
                  <Amount.uco
                    amount={input.amount}
                    uco_price_at_time={@uco_price_at_time}
                    uco_price_now={@uco_price_now}
                  />
                <% {:token, token_address, token_id} -> %>
                  <Amount.token
                    amount={input.amount}
                    token_address={token_address}
                    token_id={token_id}
                    token_properties={@token_properties}
                    socket={@socket}
                  />
              <% end %>
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
