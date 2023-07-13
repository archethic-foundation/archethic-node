defmodule ArchethicWeb.AEWeb.RootController do
  @moduledoc false

  alias ArchethicWeb.AEWeb.WebHostingController

  use ArchethicWeb.AEWeb, :controller

  def index(conn, params) do
    WebHostingController.web_hosting(conn, params)
  end
end
