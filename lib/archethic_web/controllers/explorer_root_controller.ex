defmodule ArchethicWeb.ExplorerRootController do
  @moduledoc false

  use ArchethicWeb, :controller

  def index(conn, _params), do: redirect(conn, to: "/explorer")

  def return_404(conn, _params), do: send_resp(conn, 404, "Not found")
end
