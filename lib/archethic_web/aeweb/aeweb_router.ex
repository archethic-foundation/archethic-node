defmodule ArchethicWeb.AEWebRouter do
  @moduledoc false
  use ArchethicWeb.AEWeb, :router

  alias ArchethicWeb.AEWeb.WebHostingController

  alias ArchethicWeb.Plug.ThrottleByIPHigh
  alias ArchethicWeb.Plug.ThrottleByIPandPath

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:put_secure_browser_headers)
    plug(ThrottleByIPHigh)
    plug(ThrottleByIPandPath)
  end

  scope "/aeweb" do
    get("/:address/*url_path", WebHostingController, :web_hosting)
  end
end
