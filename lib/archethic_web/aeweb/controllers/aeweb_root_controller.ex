defmodule ArchethicWeb.AEWebRootController do
  @moduledoc false

  alias ArchethicWeb.API.WebHostingController

  use ArchethicWeb, :controller

  def index(conn, params) do
    WebHostingController.web_hosting(conn, params)
  end
end
