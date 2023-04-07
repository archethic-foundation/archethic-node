defmodule ArchethicWeb.ExplorerRouter do
  @moduledoc false

  use ArchethicWeb, :router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(ArchethicWeb.PlugThrottleByIPLow)
    plug(:put_root_layout, {ArchethicWeb.LayoutView, :root})
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(ArchethicWeb.PlugThrottleByIPLow)
    plug(ArchethicWeb.GraphQLContext)
  end

  pipeline :unrestricted_api do
    plug(:accepts, ["json"])
    plug(ArchethicWeb.PlugThrottleByIPHigh)
    plug(ArchethicWeb.PlugThrottleByIPandPath)
  end

  scope "/", ArchethicWeb do
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

  scope "/explorer", ArchethicWeb do
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

  scope "/api" do
    pipe_through(:unrestricted_api)
    get("/web_hosting/:address/*url_path", ArchethicWeb.API.WebHostingController, :web_hosting)
  end

  scope "/api" do
    pipe_through(:api)

    get(
      "/last_transaction/:address/content",
      ArchethicWeb.API.TransactionController,
      :last_transaction_content
    )

    post("/origin_key", ArchethicWeb.API.OriginKeyController, :origin_key)
    post("/transaction", ArchethicWeb.API.TransactionController, :new)
    post("/transaction_fee", ArchethicWeb.API.TransactionController, :transaction_fee)

    post(
      "/transaction/contract/simulator",
      ArchethicWeb.API.TransactionController,
      :simulate_contract_execution
    )

    forward(
      "/graphiql",
      Absinthe.Plug.GraphiQL,
      schema: ArchethicWeb.GraphQLSchema,
      socket: ArchethicWeb.UserSocket
    )

    forward(
      "/",
      Absinthe.Plug,
      schema: ArchethicWeb.GraphQLSchema
    )
  end

  live_session :settings, session: {ArchethicWeb.WebUtils, :keep_remote_ip, []} do
    pipe_through(:browser)
    live("/settings", ArchethicWeb.SettingsLive)
  end

  scope "/", ArchethicWeb do
    get("/*path", ExplorerRootController, :index)
    post("/*path", ExplorerRootController, :return_404)
  end
end
