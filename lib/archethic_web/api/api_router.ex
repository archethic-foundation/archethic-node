defmodule ArchethicWeb.APIRouter do
  @moduledoc false

  alias ArchethicWeb.Plug.ThrottleByIPLow

  use ArchethicWeb.Explorer, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(ThrottleByIPLow)
    plug(ArchethicWeb.API.GraphQLContext)
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
      schema: ArchethicWeb.API.GraphQLSchema,
      socket: ArchethicWeb.UserSocket
    )

    forward(
      "/",
      Absinthe.Plug,
      schema: ArchethicWeb.API.GraphQLSchema
    )
  end
end
