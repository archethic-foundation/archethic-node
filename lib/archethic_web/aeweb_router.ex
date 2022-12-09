defmodule ArchethicWeb.AEWebRouter do
  @moduledoc false

  use ArchethicWeb, :router

  # sobelow_skip ["Config.CSRF","Config.CSP"]
  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)

    # this both can be leveraged
    # plug(:protect_from_forgery)
    # plug(
    #   :put_secure_browser_headers,
    #   %{"content-security-policy" => "default-src 'self'"}
    # )
  end

  scope "/", ArchethicWeb do
    pipe_through(:browser)

    get("/*url_path", AEWebRootController, :index)
  end
end
