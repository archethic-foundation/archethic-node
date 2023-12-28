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
          <div class="column address is-12-mobile is-6-tablet is-8-desktop">
            <%= link to: Routes.live_path(@socket, ArchethicWeb.Explorer.TransactionDetailsLive, Base.encode16(tx.address)) do %>
              <%= Base.encode16(tx.address) %>
            <% end %>
          </div>
          <div class="column list-card-item is-6-mobile is-3-tablet is-2-desktop">
            <%= format_date(tx.timestamp) %>
          </div>
          <div class="column list-card-item is-6-mobile is-3-tablet is-2-desktop">
            <%= format_transaction_type(tx.type) %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
