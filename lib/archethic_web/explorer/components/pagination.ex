defmodule ArchethicWeb.Explorer.Pagination do
  @moduledoc false

  use Phoenix.Component

  @doc """
  Variables expected:
  - current_page INTEGER
  - total_pages INTEGER

  """
  def previous_next(assigns) do
    ~H"""
    <br />
    <nav class="pagination is-right" role="navigation" aria-label="pagination">
      <div>
        <%= if @current_page > 1 do %>
          <button class="app-button" phx-value-page={@current_page - 1} phx-click="goto">
            Previous
          </button>
        <% else %>
          <button class="app-button" disabled>Previous</button>
        <% end %>
        &nbsp;
        <%= if @current_page + 1 <= @total_pages do %>
          <button class="app-button" phx-value-page={@current_page + 1} phx-click="goto">
            Next page
          </button>
        <% else %>
          <button class="app-button" disabled>Next page</button>
        <% end %>
      </div>
      <div>
        <%= @current_page %>/<%= @total_pages %>
      </div>
    </nav>
    """
  end
end
