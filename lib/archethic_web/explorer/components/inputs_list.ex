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
      <% sorted_inputs = Enum.sort_by(@inputs, & &1.consumed?, :desc) %>
      <%= for input <- sorted_inputs do %>
        <li class="columns">
          <div class="column is-narrow">
            <span class="ae-label">From</span>
            <%= link(short_address(input.from),
              to:
                Routes.live_path(
                  @socket,
                  ArchethicWeb.Explorer.TransactionDetailsLive,
                  Base.encode16(input.from)
                )
            ) %>
          </div>

          <div class="column is-narrow">
            <span class="ae-label">At</span><%= format_date(input.timestamp) %>
          </div>

          <div class="column is-narrow">
            <%= case input.type do %>
              <% :UCO -> %>
                <span class="ae-label">Amount</span>
                <Amount.uco
                  amount={input.amount}
                  uco_price_at_time={@uco_price_at_time}
                  uco_price_now={@uco_price_now}
                />
              <% {:token, token_address, token_id} -> %>
                <span class="ae-label">Amount</span>
                <Amount.token
                  amount={input.amount}
                  token_address={token_address}
                  token_id={token_id}
                  token_properties={@token_properties}
                  socket={@socket}
                />
              <% :call -> %>
                <span class="ae-label">Smart contract call</span>
              <% :state -> %>
                <span class="ae-label">Smart contract state</span>
            <% end %>
          </div>

          <div class="column is-narrow">
            <%= if input.consumed? do %>
              <span class="ae-label">
                Spent
              </span>
            <% else %>
              <%= if input.spent? do %>
                <span class="ae-label">
                  Not used then, spent now.
                </span>
              <% else %>
                <span class="ae-label">
                  Still unspent
                </span>
              <% end %>
            <% end %>
          </div>
        </li>
      <% end %>
    </ul>
    """
  end
end
