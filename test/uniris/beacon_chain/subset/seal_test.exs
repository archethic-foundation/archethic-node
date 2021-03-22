defmodule Uniris.BeaconChain.SealingTest do
  use UnirisCase

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.Subset.Seal
  alias Uniris.BeaconChain.Summary

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Message.GetBeaconSlot
  alias Uniris.P2P.Message.NotFound
  alias Uniris.P2P.Node

  import Mox

  setup do
    start_supervised!({SlotTimer, interval: "0 0 * * * *"})
    start_supervised!(Batcher)

    P2P.add_node(%Node{
      first_public_key: Crypto.node_public_key(0),
      network_patch: "AAA"
    })

    :ok
  end

  describe "link_to_previous_slot/2" do
    test "should fetch the previous slot and link it by hash" do
      MockClient
      |> expect(:send_message, fn _, %BatchRequests{requests: [%GetBeaconSlot{}]}, _ ->
        {:ok,
         %BatchResponses{responses: [{0, %Slot{subset: <<0>>, slot_time: DateTime.utc_now()}}]}}
      end)

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        geo_patch: "AAA",
        network_patch: "AAA",
        available?: true,
        enrollment_date: DateTime.utc_now()
      })

      assert %Slot{previous_hash: previous_hash} =
               Seal.link_to_previous_slot(%Slot{subset: <<0>>}, DateTime.utc_now())

      expected_hash =
        %Slot{subset: <<0>>, slot_time: DateTime.utc_now()} |> Slot.serialize() |> Crypto.hash()

      assert previous_hash == expected_hash
    end

    test "should keep the genesis hash when not previous slot is found" do
      MockClient
      |> expect(:send_message, fn _, %BatchRequests{requests: [%GetBeaconSlot{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %NotFound{}}]}}
      end)

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        geo_patch: "AAA",
        network_patch: "AAA",
        available?: true,
        enrollment_date: DateTime.utc_now()
      })

      assert %Slot{previous_hash: previous_hash} =
               Seal.link_to_previous_slot(%Slot{subset: <<0>>}, DateTime.utc_now())

      assert previous_hash == Enum.map(1..33, fn _ -> <<0>> end) |> :erlang.list_to_binary()
    end
  end

  test "new_summary/3 should create summary from the beacon slots registered" do
    me = self()

    MockDB
    |> expect(:get_beacon_slots, fn _, _ ->
      [
        %Slot{
          transaction_summaries: [
            %TransactionSummary{
              address: "@Alice2",
              type: :transfer,
              timestamp: ~U[2021-01-22 09:01:56Z]
            }
          ]
        },
        %Slot{
          transaction_summaries: [
            %TransactionSummary{
              address: "@Bob3",
              type: :transfer,
              timestamp: ~U[2021-01-22 08:50:22Z]
            }
          ],
          end_of_node_synchronizations: [
            %EndOfNodeSync{
              public_key: "NodeKey1",
              timestamp: ~U[2021-01-22 08:53:18Z]
            }
          ]
        }
      ]
    end)
    |> expect(:register_beacon_summary, fn summary ->
      send(me, {:summary, summary})
      :ok
    end)

    summary_time = DateTime.utc_now()
    assert :ok = Seal.new_summary(<<0>>, summary_time, %Slot{})

    assert_receive {:summary,
                    %Summary{
                      subset: <<0>>,
                      summary_time: ^summary_time,
                      transaction_summaries: [
                        %TransactionSummary{address: "@Bob3"},
                        %TransactionSummary{address: "@Alice2"}
                      ],
                      end_of_node_synchronizations: [
                        %EndOfNodeSync{public_key: "NodeKey1"}
                      ]
                    }}
  end
end
