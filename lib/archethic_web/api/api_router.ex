defmodule ArchethicWeb.APIRouter do
  @moduledoc false

  alias ArchethicWeb.API
  alias ArchethicWeb.API.REST
  alias ArchethicWeb.Plug.ThrottleByIPLow

  use ArchethicWeb.Explorer, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(ThrottleByIPLow)
    plug(ArchethicWeb.API.GraphQL.Context)
  end

  scope "/api/rpc", API do
    post("/", JsonRPCController, :rpc)
  end

  scope "/api", REST do
    pipe_through(:api)

    get("/last_transaction/:address/content", TransactionController, :last_transaction_content)

    post("/origin_key", OriginKeyController, :origin_key)
    post("/transaction", TransactionController, :new)
    post("/transaction_fee", TransactionController, :transaction_fee)

    post("/transaction/contract/simulator", TransactionController, :simulate_contract_execution)
  end

  scope "/api" do
    pipe_through(:api)

    forward(
      "/graphiql",
      Absinthe.Plug.GraphiQL,
      schema: ArchethicWeb.API.GraphQL.Schema,
      socket: ArchethicWeb.UserSocket
    )

    forward(
      "/",
      Absinthe.Plug,
      schema: ArchethicWeb.API.GraphQL.Schema
    )
  end
end
