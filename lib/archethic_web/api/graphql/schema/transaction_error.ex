defmodule ArchethicWeb.API.GraphQL.Schema.TransactionError do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  Transaction error context
  """
  enum :error_context do
    value(:network_issue, description: "Network problem")
    value(:invalid_transaction, description: "Transaction is invalid")
  end

  @desc """
  [TransactionError] represents an error.
  """
  object :transaction_error do
    field(:address, :address)
    field(:context, :error_context)
    field(:reason, :string)
  end
end
