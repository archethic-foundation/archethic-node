defmodule ArchethicWeb.Explorer.Components.Amount do
  @moduledoc false

  alias ArchethicWeb.ExplorerRouter.Helpers, as: Routes

  use Phoenix.Component
  use Phoenix.HTML

  import ArchethicWeb.WebUtils

  @max_symbol_len 6

  def uco(assigns = %{amount: 0}) do
    ~H"""
    <span>0 UCO</span>
    """
  end

  def uco(assigns) do
    assigns =
      assign(
        assigns,
        %{
          amount: from_bigint(assigns.amount),
          tooltip:
            format_full_usd_amount(
              assigns.amount,
              assigns.uco_price_at_time[:usd],
              assigns.uco_price_now[:usd]
            )
        }
      )

    ~H"""
    <span data-tooltip={@tooltip}><%= @amount %> UCO</span>
    """
  end

  def token(assigns) do
    decimals =
      Map.get(assigns.token_properties, assigns.token_address, %{}) |> Map.get(:decimals, 8)

    assigns =
      assign(assigns, %{
        amount: from_bigint(assigns.amount, decimals),
        token_name:
          if assigns.token_id > 0 do
            "NFT ##{assigns.token_id}"
          else
            case Map.get(assigns.token_properties, assigns.token_address, %{})
                 |> Map.get(:symbol) do
              nil ->
                short_address(assigns.token_address)

              symbol ->
                if String.length(symbol) > @max_symbol_len do
                  String.slice(symbol, 0..(@max_symbol_len - 1)) <> "..."
                else
                  symbol
                end
            end
          end
      })

    ~H"""
    <span>
      <%= @amount %>

      <%= link(@token_name,
        to:
          Routes.live_path(
            @socket,
            ArchethicWeb.Explorer.TransactionDetailsLive,
            Base.encode16(@token_address)
          )
      ) %>
    </span>
    """
  end
end
