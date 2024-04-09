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
  Date returned with the error.
  It could be any type (string, map, list, number or null)
  """
  scalar :error_data do
    serialize(& &1)
  end

  @desc """
  Details about the error
  """
  object :error_details do
    field(:code, :integer)
    field(:message, :string)
    field(:data, :error_data)
  end

  @desc """
  [TransactionError] represents an error.
  """
  object :transaction_error do
    field(:address, :address)
    field(:context, :error_context)
    field(:reason, :string, deprecate: "Field error.message will replace reason")
    field(:error, :error_details)
  end
end
