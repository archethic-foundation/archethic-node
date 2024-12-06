defmodule ArchethicWeb.API.GraphQL.Schema.BeaconChainSummary do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  [Beacon Chain Summary] represents the beacon chain aggregate for a certain date
  """

  object :beacon_chain_summary do
    field(:version, :integer)
    field(:summary_time, :timestamp)
    field(:availability_adding_time, :integer)
    field(:p2p_availabilities, :p2p_availabilities)
    field(:transaction_summaries, list_of(:transaction_summary))
  end

  @desc """
  [Transaction Summary] Represents transaction header or extract to summarize it
  """
  object :transaction_summary do
    field(:timestamp, :timestamp)
    field(:address, :address)
    field(:movements_addresses, list_of(:address))
    field(:type, :string)
    field(:fee, :integer)
    field(:validation_stamp_checksum, :sha256_hash)
  end

  scalar :p2p_availabilities do
    serialize(& &1)
  end
end
