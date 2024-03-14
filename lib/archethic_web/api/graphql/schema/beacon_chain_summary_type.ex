defmodule ArchethicWeb.API.GraphQL.Schema.BeaconChainSummary do
  @moduledoc false

  use Absinthe.Schema.Notation
  alias Archethic.BeaconChain.SummaryAggregate

  @desc """
  [Beacon Chain Summary] represents the beacon chain aggregate for a certain date
  """

  @default_limit 100

  object :beacon_chain_summary do
    field(:version, :integer)
    field(:summary_time, :timestamp)
    field(:availability_adding_time, :integer)
    field(:p2p_availabilities, :p2p_availabilities)

    field(:transaction_summaries, list_of(:transaction_summary)) do
      arg(:paging_offset, :non_neg_integer)
      arg(:limit, :pos_integer)

      resolve(fn args,
                 %{
                   source: %SummaryAggregate{
                     replication_attestations: attestations
                   }
                 } ->
        limit = Map.get(args, :limit, @default_limit)
        paging_offset = Map.get(args, :paging_offset, 0)

        # TODO: Replace transaction summaries by attestations
        result =
          attestations
          |> Stream.map(& &1.transaction_summary)
          |> Stream.drop(paging_offset)
          |> Enum.take(limit)

        {:ok, result}
      end)
    end
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
