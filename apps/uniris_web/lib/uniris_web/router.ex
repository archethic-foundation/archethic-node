defmodule UnirisWeb.Router do
  use UnirisWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/explorer", UnirisWeb do
    pipe_through :browser

    get "/", ExplorerController, :index
    get "/transaction/:address", ExplorerController, :show
    get "/search", ExplorerController, :search
  end

  scope "/api" do
    pipe_through :api

    get "/last_transaction/:address/content", UnirisWeb.TransactionController, :last_transaction_content

    forward "/graphiql",
            Absinthe.Plug.GraphiQL,
            schema: Schema,
            socket: UnirisWeb.UserSocket

    forward "/",
            Absinthe.Plug,
            schema: UnirisWeb.Schema
  end
end
