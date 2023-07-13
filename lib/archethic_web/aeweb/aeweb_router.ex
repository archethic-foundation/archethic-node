defmodule ArchethicWeb.AEWebRouter do
  @moduledoc false

  alias ArchethicWeb.Plug.ThrottleByIPHigh
  alias ArchethicWeb.Plug.ThrottleByIPandPath

  use ArchethicWeb.AEWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_secure_browser_headers)
    plug(ThrottleByIPHigh)
    plug(ThrottleByIPandPath)
  end

  scope "/", ArchethicWeb.AEWeb do
    pipe_through(:browser)

    get("/*url_path", RootController, :index)
  end
end
