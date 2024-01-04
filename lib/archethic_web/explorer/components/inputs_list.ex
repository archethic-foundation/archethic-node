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
    <ul>
      <%= for input <- @inputs do %>
        <li class="columns is-mobile is-multiline">
          <div class="column is-3-tablet is-6-mobile">
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
          </div>

          <div class="column is-narrow-tablet is-6-mobile">
            <%= link(short_address(input.from),
              to:
                Routes.live_path(
                  @socket,
                  ArchethicWeb.Explorer.TransactionDetailsLive,
                  Base.encode16(input.from)
                )
            ) %>
          </div>

          <div class="column is-narrow-tablet is-6-mobile"><%= format_date(input.timestamp) %></div>
          <div class="column is-narrow-tablet is-6-mobile">
            <%= if input.spent? do %>
              <span class="tag is-danger">Spent</span>
            <% else %>
              <span class="tag is-success">Unspent</span>
            <% end %>
          </div>
        </li>
      <% end %>
    </ul>
    """
  end
end
