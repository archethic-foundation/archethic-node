defmodule ArchEthicWeb.Router do
  @moduledoc false

  use ArchEthicWeb, :router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:put_root_layout, {ArchEthicWeb.LayoutView, :root})
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  # Add the on chain implementation of the archethic.io at the root of the webserver
  # TODO: review to put it on every node or as proxy somewhere forwarding to a specific transaction chain explorer
  scope "/", ArchEthicWeb do
    pipe_through(:browser)

    get("/", RootController, :index)
    get("/up", UpController, :up)
    get("/metrics", MetricsController, :index)
    live("/metrics/dashboard", NetworkMetricsLive)

    if Mix.env() == :dev do
      live_dashboard("/dashboard",
        metrics: ArchEthic.Telemetry,
        additional_pages: [
          # broadway: BroadwayDashboard
        ]
      )
    end

    get("/faucet", FaucetController, :index)
    post("/faucet", FaucetController, :create_transfer)
  end

  scope "/explorer", ArchEthicWeb do
    pipe_through(:browser)

    live("/", ExplorerIndexLive)

    live("/transactions", TransactionListLive)
    live("/transaction/:address", TransactionDetailsLive)

    get("/chain", ExplorerController, :chain)
    live("/chain/oracle", OracleChainLive)
    live("/chain/beacon", BeaconChainLive)

    live("/nodes", NodeListLive)
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
      ArchEthicWeb.API.TransactionController,
      :last_transaction_content
    )

    post("/transaction", ArchEthicWeb.API.TransactionController, :new)
    post("/transaction_fee", ArchEthicWeb.API.TransactionController, :transaction_fee)

    forward(
      "/graphiql",
      Absinthe.Plug.GraphiQL,
      schema: ArchEthicWeb.GraphQLSchema,
      socket: ArchEthicWeb.UserSocket
    )

    forward(
      "/",
      Absinthe.Plug,
      schema: ArchEthicWeb.GraphQLSchema
    )
  end
end
