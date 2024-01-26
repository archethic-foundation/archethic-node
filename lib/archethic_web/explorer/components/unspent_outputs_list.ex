defmodule ArchethicWeb.Explorer.Components.UnspentOutputList do
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
      <%= for utxo <- @utxos do %>
        <li class="columns">
          <div class="column is-narrow">
            <span class="ae-label">From</span>
            <%= link(short_address(utxo.from),
              to:
                Routes.live_path(
                  @socket,
                  ArchethicWeb.Explorer.TransactionDetailsLive,
                  Base.encode16(utxo.from)
                )
            ) %>
          </div>

          <div class="column is-narrow">
            <span class="ae-label">At</span>
            <%= format_date(utxo.timestamp) %>
          </div>

          <div class="column is-narrow">
            <%= case utxo.type do %>
              <% :UCO -> %>
                <span class="ae-label">Amount</span>
                <Amount.uco
                  amount={utxo.amount}
                  uco_price_at_time={@uco_price_at_time}
                  uco_price_now={@uco_price_now}
                />
              <% {:token, token_address, token_id} -> %>
                <span class="ae-label">Amount</span>
                <Amount.token
                  amount={utxo.amount}
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

          <%= if @display_status? do %>
            <div class="column is-narrow">
              <%= if ArchethicWeb.Explorer.TransactionDetailsLive.utxo_spent?(utxo, @inputs) do %>
                <span class="tag is-danger mono">Spent&nbsp;&nbsp;</span>
              <% else %>
                <span class="tag is-success mono">Unspent</span>
              <% end %>
            </div>
          <% end %>
        </li>
      <% end %>
    </ul>
    """
  end
end
