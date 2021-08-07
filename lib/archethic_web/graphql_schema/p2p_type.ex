defmodule ArchEthicWeb.GraphQLSchema.P2PType do
  @moduledoc false

  use Absinthe.Schema.Notation

  object :node do
    field(:first_public_key, :hex)
    field(:last_public_key, :hex)
    field(:ip, :string)
    field(:port, :integer)
    field(:reward_address, :hex)
    field(:available, :boolean)
    field(:authorized, :boolean)
    field(:geo_patch, :string)
    field(:network_patch, :string)
    field(:average_availability, :float)
    field(:enrollment_date, :timestamp)
    field(:authorization_date, :timestamp)
  end
end
