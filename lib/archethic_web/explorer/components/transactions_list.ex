defmodule ArchethicWeb.Explorer.Components.TransactionsList do
  @moduledoc false

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.TransactionSummary

  alias ArchethicWeb.ExplorerRouter.Helpers, as: Routes
  alias ArchethicWeb.Explorer.Components.Amount

  use Phoenix.Component
  use Phoenix.HTML

  import ArchethicWeb.Explorer.ExplorerView
  import ArchethicWeb.WebUtils

  def display_all(assigns) do
    assigns =
      assign(
        assigns,
        %{
          total:
            if Map.has_key?(assigns, :total) do
              assigns.total
            else
              0
            end,
          page:
            if Map.has_key?(assigns, :page) do
              assigns.page
            else
              1
            end
        }
      )

    ~H"""
    <% tx_count = length(@transactions) %>
    <div
      class="ae-box ae-purple shadow"
      phx-hook={
        if tx_count < assigns.total do
          "InfiniteScroll"
        else
          ""
        end
      }
      data-page={@page}
      id="infinite_scroll"
    >
      <ul>
        <li class="columns is-mobile th">
          <div class="column is-3-tablet is-6-mobile">Address</div>
          <div class="column is-3-tablet is-hidden-mobile">Genesis</div>
          <div class="column is-6-mobile">Type</div>
          <div class="column is-hidden-mobile">Date (UTC)</div>
          <div class="column is-hidden-mobile">Fee</div>
        </li>

        <%= for tx <- @transactions do %>
          <li class="columns is-mobile is-multiline">
            <div class="column is-3-tablet is-6-mobile">
              <%= link(short_address(tx.address),
                to:
                  Routes.live_path(
                    @socket,
                    ArchethicWeb.Explorer.TransactionDetailsLive,
                    Base.encode16(tx.address)
                  )
              ) %>
            </div>
            <div class="column is-3-tablet is-hidden-mobile">
              <%= link(short_address(get_genesis(tx)),
                to:
                  Routes.live_path(
                    @socket,
                    ArchethicWeb.Explorer.TransactionChainLive,
                    address: Base.encode16(get_genesis(tx))
                  )
              ) %>
            </div>
            <div class="column is-6-mobile"><%= format_transaction_type(tx.type) %></div>
            <div class="column is-hidden-mobile">
              <%= format_date(get_timestamp(tx), display_utc: false) %>
            </div>
            <div class="column is-hidden-mobile">
              <Amount.uco amount={get_fee(tx)} uco_price_now={@uco_price_now} />
            </div>
          </li>
        <% end %>
      </ul>

      <%= if tx_count < @total do %>
        <div phx-click="load-more">Click to load more transactions</div>
      <% end %>
    </div>
    """
  end

  # beacon
  defp get_timestamp(%TransactionSummary{timestamp: timestamp}), do: timestamp

  # chain page
  defp get_timestamp(%Transaction{validation_stamp: %ValidationStamp{timestamp: timestamp}}),
    do: timestamp

  # nss/reward/oracle/origin page
  defp get_timestamp(map) do
    Map.get(map, :timestamp)
  end

  defp get_genesis(%Transaction{
         validation_stamp: %ValidationStamp{genesis_address: genesis_address}
       }),
       do: genesis_address

  defp get_genesis(%TransactionSummary{genesis_address: genesis_address}),
    do: genesis_address

  defp get_genesis(map) do
    Map.get(map, :genesis_address)
  end

  # reward/nss/home...
  defp get_fee(%TransactionSummary{fee: fee}), do: fee

  # chain page
  defp get_fee(%Transaction{
         validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: fee}}
       }),
       do: fee

  # oracle/origin page
  defp get_fee(map) do
    Map.get(map, :fee, 0)
  end
end
