defmodule ArchethicWeb.Explorer.Components.Amount do
  @moduledoc false

  alias ArchethicWeb.ExplorerRouter.Helpers, as: Routes

  use Phoenix.Component
  use Phoenix.HTML

  import ArchethicWeb.WebUtils

  @max_symbol_len 6

  def uco(assigns = %{amount: 0}) do
    ~H"""
    <span class="mono" data-tooltip="at time: 0$, now: 0$">
      0 <span class="tag is-gradient mono">UCO</span>
    </span>
    """
  end

  def uco(assigns) do
    assigns =
      assign(assigns, %{amount: from_bigint(assigns.amount), tooltip: get_uco_tooltip(assigns)})

    ~H"""
    <span class="mono" data-tooltip={@tooltip}>
      <%= @amount %> <span class="tag is-gradient mono">UCO</span>
    </span>
    """
  end

  def token(
        assigns = %{
          amount: amount,
          token_properties: token_properties,
          token_address: token_address,
          token_id: token_id
        }
      ) do
    token_properties = Map.get(token_properties, token_address, %{})
    decimals = Map.get(token_properties, :decimals, 8)
    token_name_max_length = Map.get(assigns, :max_length, @max_symbol_len)

    assigns =
      assign(assigns, %{
        amount: from_bigint(amount, decimals),
        token_name:
          get_token_name(token_properties, token_address, token_id, token_name_max_length)
      })

    ~H"""
    <span class="mono">
      <%= @amount %>

      <%= link(to:
          Routes.live_path(
            @socket,
            ArchethicWeb.Explorer.TransactionDetailsLive,
            Base.encode16(@token_address)
          )
      ) do %>
        <span class="tag is-gradient mono"><%= @token_name %></span>
      <% end %>
    </span>
    """
  end

  defp get_token_name(token_properties, token_address, token_id, token_name_max_length) do
    case Map.get(token_properties, :symbol) do
      nil ->
        short_address(token_address)

      symbol ->
        text =
          if String.length(symbol) > token_name_max_length do
            String.slice(symbol, 0..(token_name_max_length - 1)) <> "..."
          else
            symbol
          end

        text = text <> if token_id > 0, do: " ##{token_id}", else: ""

        content_tag(
          "span",
          text,
          "data-tooltip": symbol <> " minted at " <> Base.encode16(token_address),
          class: "mono"
        )
    end
  end

  defp get_uco_tooltip(%{
         uco_price_at_time: uco_price_at_time,
         uco_price_now: uco_price_now,
         amount: amount
       })
       when uco_price_at_time != nil do
    format_full_usd_amount(amount, uco_price_at_time[:usd], uco_price_now[:usd])
  end

  defp get_uco_tooltip(%{uco_price_now: uco_price_now, amount: amount}) do
    "now: " <> format_usd_amount(amount, uco_price_now[:usd])
  end
end
