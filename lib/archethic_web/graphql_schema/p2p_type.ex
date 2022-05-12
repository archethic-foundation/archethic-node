defmodule ArchethicWeb.GraphQLSchema.P2PType do
  @moduledoc false

  use Absinthe.Schema.Notation

  object :node do
    field(:first_public_key, :public_key)
    field(:last_public_key, :public_key)
    field(:ip, :string)
    field(:port, :integer)
    field(:reward_address, :address)
    field(:available, :boolean)
    field(:authorized, :boolean)
    field(:geo_patch, :string)
    field(:network_patch, :string)
    field(:average_availability, :float)
    field(:enrollment_date, :timestamp)
    field(:authorization_date, :timestamp)
    field(:origin_public_key, :public_key)
  end
end
