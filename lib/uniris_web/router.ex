defmodule UnirisWeb.Router do
  @moduledoc false

  use UnirisWeb, :router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:put_root_layout, {UnirisWeb.LayoutView, :root})
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  # Add the on chain implementation of the uniris.io at the root of the webserver
  # TODO: review to put it on every node or as proxy somewhere forwarding to a specific transaction chain explorer
  scope "/", UnirisWeb do
    pipe_through(:browser)

    get("/", RootController, :index)
    get("/up", UpController, :up)
    get("/metrics", MetricsController, :index)
    live_dashboard("/dashboard", metrics: Uniris.Telemetry)
  end

  scope "/explorer", UnirisWeb do
    pipe_through(:browser)

    live("/", ExplorerIndexLive)
    live("/transactions", TransactionListLive)
    live("/transaction/:address", TransactionDetailsLive)
    get("/chain", ExplorerController, :chain)
    get("/node", NodeController, :index)
    get("/node/:public_key", NodeController, :show)
    live("/code/viewer", CodeViewerLive)
    live("/code/proposals", CodeProposalsLive)
    live("/code/proposal/:address", CodeProposalDetailsLive)
    get("/code/download", CodeController, :download)
  end

  scope "/api" do
    pipe_through(:api)

    get(
      "/last_transaction/:address/content",
      UnirisWeb.API.TransactionController,
      :last_transaction_content
    )

    post("/transaction", UnirisWeb.API.TransactionController, :new)

    forward(
      "/graphiql",
      Absinthe.Plug.GraphiQL,
      schema: UnirisWeb.GraphQLSchema,
      socket: UnirisWeb.UserSocket
    )

    forward(
      "/",
      Absinthe.Plug,
      schema: UnirisWeb.GraphQLSchema
    )
  end
end
