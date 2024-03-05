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
            <span class="ae-label">Amount</span>
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

          <div class="column is-narrow">
            <%= if input.consumed? do %>
              <span class="tag is-danger mono" data-tooltip="consumed by this transaction">Used&nbsp;&nbsp;</span>
            <% else %>
              <span class="tag is-success mono" data-tooltip="not used by this transaction">Unused&nbsp;&nbsp;</span>
            <% end %>
            <%= if input.spent? do %>
              <span class="tag is-danger mono" data-tooltip="globally spent in the chain">Spent&nbsp;&nbsp;</span>
            <% end %>
          </div>
        </li>
      <% end %>
    </ul>
    """
  end
end
