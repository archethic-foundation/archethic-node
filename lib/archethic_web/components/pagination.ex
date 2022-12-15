defmodule ArchethicWeb.Pagination do
  @moduledoc false

  use Phoenix.Component

  @doc """
  Variables expected:
  - current_page INTEGER
  - total_pages INTEGER

  """
  def previous_next(assigns) do
    ~H"""
    <nav class="pagination is-right" role="navigation" aria-label="pagination">
      <%= if @current_page > 1 do %>
        <a class="pagination-previous" phx-value-page={@current_page - 1} phx-click="goto">Previous</a>
      <% else %>
        <a class="pagination-previous is-disabled">Previous</a>
      <% end %>

      <%= if @current_page + 1 <= @total_pages do %>
        <a class="pagination-next" phx-value-page={@current_page + 1} phx-click="goto">Next page</a>
      <% else %>
        <a class="pagination-next is-disabled">Next page</a>
      <% end %>

      <p class="pagination-list has-text-white">
        Page <%= @current_page %> on <%= @total_pages %>
      </p>
    </nav>
    """
  end
end
