defmodule ArchethicWeb.GraphQLSchema.DateTimeType do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  The [Timestamp] scalar type represents a UNIX timestamp in seconds
  """
  scalar :timestamp do
    serialize(&DateTime.to_unix/1)
  end
end
