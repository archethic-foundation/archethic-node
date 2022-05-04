defmodule ArchethicWeb.Router do
  @moduledoc false

  use ArchethicWeb, :router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:put_root_layout, {ArchethicWeb.LayoutView, :root})
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  # Add the on chain implementation of the archethic.io at the root of the webserver
  # TODO: review to put it on every node or as proxy somewhere forwarding to a specific transaction chain explorer
  scope "/", ArchethicWeb do
    pipe_through(:browser)

    get("/", RootController, :index)
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

    live("/transactions", TransactionListLive)
    live("/transaction/:address", TransactionDetailsLive)

    get("/chain", ExplorerController, :chain)
    live("/chain/oracle", OracleChainLive)
    live("/chain/beacon", BeaconChainLive)

    live("/nodes", NodeListLive)
    live("/nodes/worldmap", WorldMapLive)
    live("/node/:public_key", NodeDetailsLive)

    live("/code/viewer", CodeViewerLive)
    live("/code/proposals", CodeProposalsLive)
    live("/code/proposal/:address", CodeProposalDetailsLive)
    get("/code/download", CodeController, :download)
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
end
