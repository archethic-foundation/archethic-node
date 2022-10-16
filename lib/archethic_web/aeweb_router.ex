defmodule ArchethicWeb.AEWebRouter do
  @moduledoc false

  use ArchethicWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_secure_browser_headers)
  end

  scope "/", ArchethicWeb do
    pipe_through(:browser)

    get("/*url_path", AEWebRootController, :index)
  end
end
