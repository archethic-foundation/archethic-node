defmodule ArchethicWeb.Explorer.Components.TransactionsList do
  @moduledoc false

  alias ArchethicWeb.ExplorerRouter.Helpers, as: Routes

  use Phoenix.Component
  use Phoenix.HTML

  import ArchethicWeb.Explorer.ExplorerView
  import ArchethicWeb.WebUtils

  def display_all(assigns) do
    ~H"""
    <div class="ae-box ae-purple shadow">
      <%= for tx <- @transactions do %>
        <div class="columns">
          <div class="column">
            <%= link(short_address(tx.address),
              to:
                Routes.live_path(
                  @socket,
                  ArchethicWeb.Explorer.TransactionDetailsLive,
                  Base.encode16(tx.address)
                )
            ) %>
          </div>
          <div class="column mono">
            <%= format_date(tx.timestamp) %>
          </div>
          <div class="column">
            <%= format_transaction_type(tx.type) %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
