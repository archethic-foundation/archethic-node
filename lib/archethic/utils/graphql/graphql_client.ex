defmodule ArchEthic.Utils.GraphQL.GraphqlClient do
<<<<<<< HEAD
=======
  @moduledoc false

>>>>>>> temp
  use CommonGraphQLClient.Client,
    otp_app: :archethic,
    mod: ArchEthic.Utils.GraphQL.GraphqlServerAPI

  @gql """
  query {
   transactions{
    address
    }
  }
  """
  defp handle(:list, :transactions) do
    do_post(
      :transactions,
      GraphqlSchema.Transaction,
      @gql
    )
  end

  defp handle_subscribe_to({:transactionConfirmed, %{address: address}, _from}, mod) do
    IO.inspect(address,
      label: "<---------- [address] ---------->",
      limit: :infinity,
      printable_limit: :infinity
    )

    subscription_query = """
      subscription {
<<<<<<< HEAD
       transactionConfirmed(address: #{address})
=======
       transactionConfirmed(address: \"#{address}\")
       {
         nbConfirmations
         }
>>>>>>> temp
      }
    """

    IO.inspect(subscription_query,
      label: "<---------- [subscription_query] ---------->",
      limit: :infinity,
      printable_limit: :infinity
    )

    do_subscribe(
      mod,
      :transactionConfirmed,
      GraphqlSchema.TransactionConfirmed,
      subscription_query
    )
  end
end

defmodule ArchEthic.Utils.GraphQL.GraphqlSchema.Transaction do
<<<<<<< HEAD
=======
  @moduledoc false
>>>>>>> temp
  use CommonGraphQLClient.Schema

  api_schema do
    field(:address, :string)
  end

  @cast_params ~w(
    address
  )a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @cast_params)
  end
end

defmodule ArchEthic.Utils.GraphQL.GraphqlSchema.TransactionConfirmed do
  use CommonGraphQLClient.Schema

  api_schema do
    field(:nbConfirmations, :string)
  end

  @cast_params ~w(
    nbConfirmations
  )a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @cast_params)
  end
end
