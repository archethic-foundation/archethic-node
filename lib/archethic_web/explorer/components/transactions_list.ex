defmodule ArchethicWeb.Explorer.Components.TransactionsList do
  @moduledoc false

  alias ArchethicWeb.ExplorerRouter.Helpers, as: Routes
  alias ArchethicWeb.Explorer.Components.Amount

  use Phoenix.Component
  use Phoenix.HTML

  import ArchethicWeb.Explorer.ExplorerView
  import ArchethicWeb.WebUtils

  def display_all(assigns) do
    ~H"""
    <div class="ae-box ae-purple shadow">
      <table class="table ae-table is-fullwidth is-hoverable">
        <thead>
          <tr>
            <th>Address</th>
            <th>Type</th>
            <th>Date (UTC)</th>
            <th>Fee</th>
          </tr>
        </thead>
        <tbody>
          <%= for tx <- @transactions do %>
            <tr>
              <td>
                <%= link(short_address(tx.address),
                  to:
                    Routes.live_path(
                      @socket,
                      ArchethicWeb.Explorer.TransactionDetailsLive,
                      Base.encode16(tx.address)
                    )
                ) %>
              </td>
              <td><%= format_transaction_type(tx.type) %></td>
              <td><%= format_date(tx.timestamp, display_utc: false) %></td>
              <td>
                <Amount.uco amount={Map.get(tx, :fee, 0)} />
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end
end
