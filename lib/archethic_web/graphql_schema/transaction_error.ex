defmodule ArchethicWeb.GraphQLSchema.TransactionError do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  [TransactionError] represents an error.
  """
  object :transaction_error do
    field(:address, :address)
    field(:error, :string)
  end
end
