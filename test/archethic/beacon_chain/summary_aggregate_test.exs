defmodule Archethic.BeaconChain.SummaryAggregateTest do
  use ArchethicCase

  alias Archethic.BeaconChain.SummaryAggregate
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.TransactionChain.TransactionSummary

  doctest SummaryAggregate

  describe "aggregate/1" do
    test "should aggregate multiple network patches into a single one" do
      P2P.add_and_connect_node(%Node{
        first_public_key: <<0::8, 0::8, 0::8, :crypto.strong_rand_bytes(31)::binary>>,
        last_public_key: <<0::8, 0::8, 0::8, :crypto.strong_rand_bytes(31)::binary>>,
        ip: {127, 0, 0, 1},
        port: 3000
      })

      P2P.add_and_connect_node(%Node{
        first_public_key: <<0::8, 0::8, 0::8, :crypto.strong_rand_bytes(31)::binary>>,
        last_public_key: <<0::8, 0::8, 0::8, :crypto.strong_rand_bytes(31)::binary>>,
        ip: {127, 0, 0, 1},
        port: 3001
      })

      assert %SummaryAggregate{
               p2p_availabilities: %{
                 <<0>> => %{
                   node_availabilities: <<>>,
                   node_average_availabilities: [],
                   end_of_node_synchronizations: [],
                   network_patches: ["ABC", "DEF"]
                 }
               }
             } =
               %SummaryAggregate{
                 p2p_availabilities: %{
                   <<0>> => %{
                     node_availabilities: [],
                     node_average_availabilities: [],
                     end_of_node_synchronizations: [],
                     network_patches: [["ABC", "DEF"], ["ABC", "DEF"]]
                   }
                 }
               }
               |> SummaryAggregate.aggregate()
    end

    test "should aggregate multiple different network patches into a single one" do
      P2P.add_and_connect_node(%Node{
        first_public_key: <<0::8, 0::8, 0::8, :crypto.strong_rand_bytes(31)::binary>>,
        last_public_key: <<0::8, 0::8, 0::8, :crypto.strong_rand_bytes(31)::binary>>,
        ip: {127, 0, 0, 1},
        port: 3000
      })

      P2P.add_and_connect_node(%Node{
        first_public_key: <<0::8, 0::8, 0::8, :crypto.strong_rand_bytes(31)::binary>>,
        last_public_key: <<0::8, 0::8, 0::8, :crypto.strong_rand_bytes(31)::binary>>,
        ip: {127, 0, 0, 1},
        port: 3001
      })

      assert %SummaryAggregate{
               p2p_availabilities: %{
                 <<0>> => %{
                   node_availabilities: <<>>,
                   node_average_availabilities: [],
                   end_of_node_synchronizations: [],
                   network_patches: ["9C6", "DEF"]
                 }
               }
             } =
               %SummaryAggregate{
                 p2p_availabilities: %{
                   <<0>> => %{
                     node_availabilities: [],
                     node_average_availabilities: [],
                     end_of_node_synchronizations: [],
                     network_patches: [
                       ["ABC", "DEF"],
                       ["C90", "DEF"],
                       ["FFF", "DEF"],
                       ["000", "DEF"]
                     ]
                   }
                 }
               }
               |> SummaryAggregate.aggregate()
    end
  end
end
