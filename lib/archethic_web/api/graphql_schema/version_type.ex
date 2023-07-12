defmodule ArchethicWeb.GraphQLSchema.Version do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  [Version] represents code, transaction and protocol version
  """
  object :version do
    field(:code, :string)
    field(:transaction, :string)
    field(:protocol, :string)
  end
end
