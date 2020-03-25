defmodule UnirisWeb.Router do
  use UnirisWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api" do
    pipe_through :api

    forward "/graphiql",
            Absinthe.Plug.GraphiQL,
            schema: UnirisWeb.Schema,
            socket: UnirisWeb.UserSocket

    forward "/",
            Absinthe.Plug,
            schema: UnirisWeb.Schema
  end
end
