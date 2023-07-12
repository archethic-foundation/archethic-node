defmodule ArchethicWeb.GraphQLSchema.OracleData do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  [OracleData] represents an oracle data.
  """
  object :oracle_data do
    field(:services, :oracle_services)
    field(:timestamp, :timestamp)
  end

  object :oracle_services do
    field(:uco, :uco_data)
  end

  object :uco_data do
    field(:usd, :float)
    field(:eur, :float)
  end
end
