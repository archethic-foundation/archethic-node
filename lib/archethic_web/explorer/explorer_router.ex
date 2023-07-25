defmodule ArchethicWeb.ExplorerRouter do
  @moduledoc false

  alias ArchethicWeb.Explorer

  alias ArchethicWeb.Plug.ThrottleByIPLow

  use ArchethicWeb.Explorer, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(ThrottleByIPLow)
    plug(:put_root_layout, {Explorer.LayoutView, :root})
  end

  scope "/", Explorer do
    pipe_through(:browser)

    get("/", ExplorerRootController, :index)
    get("/up", UpController, :up)
    get("/metrics", MetricsController, :index)
    live("/metrics/dashboard", DashboardLive)

    if Mix.env() == :dev do
      live_dashboard("/dashboard",
        metrics: Archethic.Telemetry,
        additional_pages: [
          # broadway: BroadwayDashboard
        ]
      )
    end

    get("/faucet", FaucetController, :index)
    post("/faucet", FaucetController, :create_transfer)
  end

  scope "/explorer", Explorer do
    pipe_through(:browser)

    live("/", ExplorerIndexLive)

    live("/transaction/:address", TransactionDetailsLive)

    live("/chain", TransactionChainLive)
    live("/chain/oracle", OracleChainLive)
    live("/chain/beacon", BeaconChainLive)
    live("/chain/rewards", RewardChainLive)
    live("/chain/node_shared_secrets", NodeSharedSecretsChainLive)

    live("/chain/origin", OriginChainLive)

    live("/nodes", NodeListLive)
    live("/nodes/worldmap", WorldMapLive)
    live("/node/:public_key", NodeDetailsLive)

    live("/code/viewer", CodeViewerLive)
    live("/code/proposals", CodeProposalsLive)
    live("/code/proposal/:address", CodeProposalDetailsLive)
    get("/code/download", CodeController, :download)
  end

  live_session :settings, session: {ArchethicWeb.WebUtils, :keep_remote_ip, []} do
    pipe_through(:browser)
    live("/settings", ArchethicWeb.Explorer.SettingsLive)
  end

  scope "/", Explorer do
    get("/*path", ExplorerRootController, :index)
    post("/*path", ExplorerRootController, :return_404)
  end
end
