defmodule Archethic.SelfRepair.NotifierTest do
  use ArchethicCase

  alias Archethic.{
    BeaconChain.SummaryTimer,
    BeaconChain.SummaryAggregate,
    Crypto,
    P2P,
    P2P.Node,
    SelfRepair.Notifier
  }

  alias Archethic.P2P.Message.{
    ReplicateTransaction,
    Ok,
    GetBeaconSummariesAggregate,
    NotFound
  }

  alias Archethic.TransactionChain.{
    Transaction,
    Transaction.ValidationStamp,
    TransactionSummary
  }

  import Mox

  describe "SelfRepair.Notifier: Repair txns" do
    setup do
      start_supervised!({SummaryTimer, interval: "0 0 0 * * * *"})
      :ok
    end

    test "when a node is becoming offline new nodes should receive transaction to replicate" do
      P2P.add_and_connect_node(%Node{
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        ip: {127, 0, 0, 1},
        port: 3000,
        authorized?: true,
        authorization_date: ~U[2022-02-01 00:00:00Z],
        enrollment_date: ~U[2022-02-01 00:00:00Z],
        geo_patch: "AAA",
        available?: true
      })

      P2P.add_and_connect_node(%Node{
        first_public_key: "node2",
        last_public_key: "node2",
        ip: {127, 0, 0, 1},
        port: 3001,
        authorized?: true,
        authorization_date: ~U[2022-02-01 00:00:00Z],
        enrollment_date: ~U[2022-02-01 00:00:00Z],
        geo_patch: "CCC",
        available?: true
      })

      P2P.add_and_connect_node(%Node{
        first_public_key: "node3",
        last_public_key: "node3",
        ip: {127, 0, 0, 1},
        port: 3002,
        authorized?: true,
        authorization_date: ~U[2022-02-03 00:00:00Z],
        enrollment_date: ~U[2022-02-03 00:00:00Z],
        geo_patch: "DDD",
        available?: true
      })

      {:ok, pid} = Notifier.start_link()

      MockDB
      |> expect(:list_transactions, fn _ ->
        [
          %Transaction{
            address: "@Alice1",
            type: :transfer,
            validation_stamp: %ValidationStamp{
              timestamp: ~U[2022-02-01 12:54:00Z]
            }
          }
        ]
      end)

      me = self()

      MockClient
      |> expect(:send_message, fn %Node{first_public_key: "node3"},
                                  %ReplicateTransaction{
                                    transaction: %Transaction{address: "@Alice1"}
                                  },
                                  _ ->
        send(me, :tx_replicated)
        %Ok{}
      end)

      send(
        pid,
        {:node_update,
         %Node{
           first_public_key: "node2",
           available?: false,
           authorized?: true,
           authorization_date: ~U[2022-02-01 00:00:00Z]
         }}
      )

      assert_receive :tx_replicated
    end
  end

  describe "NotifierTest: Repair SummaryAggregates" do
    setup do
      # p2p_context()
      start_supervised!({SummaryTimer, interval: "0 0 0 * * * *"})

      :ok
    end

    test "when a node is becoming offline new nodes should ask for to Summary_Aggregates" do
      me = self()

      P2P.add_and_connect_node(%Node{
        first_public_key: "node00",
        last_public_key: "node01",
        ip: {127, 0, 0, 1},
        port: 3000,
        authorized?: true,
        authorization_date: ~U[2022-10-05 00:00:00Z],
        geo_patch: "CCC",
        enrollment_date: ~U[2022-10-05 00:00:00Z],
        available?: true
      })

      P2P.add_and_connect_node(%Node{
        first_public_key: "node10",
        last_public_key: "node11",
        ip: {127, 0, 0, 1},
        port: 3001,
        authorized?: true,
        authorization_date: ~U[2022-10-10 00:00:00Z],
        geo_patch: "CCC",
        enrollment_date: ~U[2022-10-10 00:00:00Z],
        available?: true
      })

      P2P.add_and_connect_node(%Node{
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        ip: {127, 0, 0, 2},
        port: 3002,
        authorized?: true,
        authorization_date: ~U[2022-10-15 00:00:00Z],
        geo_patch: "CCC",
        available?: true,
        enrollment_date: ~U[2022-10-15 00:00:00Z]
      })

      summary_aggregate_date = ~U[2022-10-11 00:00:00Z]
      {:ok, pid} = Notifier.start_link()

      # Archethic.PubSub.register_to_node_update()
      P2P.set_node_globally_unavailable("node10")
      # assert_receive {:node_update, %Node{first_public_key: "node10"}}

      aggregate = %SummaryAggregate{
        summary_time: summary_aggregate_date,
        transaction_summaries: [
          %TransactionSummary{
            address:
              <<0, 0, 120, 123, 229, 13, 144, 130, 230, 18, 17, 45, 244, 92, 226, 11, 104, 226,
                249, 138, 85, 71, 127, 190, 20, 186, 69, 131, 97, 194, 30, 71, 116>>,
            type: :transfer,
            timestamp: summary_aggregate_date,
            fee: 10_000_000
          }
        ],
        p2p_availabilities: %{
          <<0>> => %{
            node_availabilities: <<1::1, 0::1, 1::1>>,
            node_average_availabilities: [0.5, 0.7, 0.8],
            end_of_node_synchronizations: [
              <<0, 1, 57, 98, 198, 202, 155, 43, 217, 149, 5, 213, 109, 252, 111, 87, 170, 54,
                211, 178, 208, 5, 184, 33, 193, 167, 91, 160, 131, 129, 117, 45, 242>>
            ]
          }
        }
      }

      MockDB
      |> stub(:list_transactions, fn _ ->
        [
          %Transaction{
            address: "@Alice1",
            type: :transfer,
            validation_stamp: %ValidationStamp{
              timestamp: ~U[2022-10-10 12:00:00Z]
            }
          }
        ]
      end)
      |> stub(:write_beacon_summaries_aggregate, fn aggregate_to_write ->
        send(me, {:aggreate_write, aggregate_to_write})
        :ok
      end)

      MockClient
      |> stub(
        :send_message,
        fn
          %Node{first_public_key: "node00"}, %GetBeaconSummariesAggregate{}, _ ->
            {:ok, aggregate}

          _, _, _ ->
            %NotFound{}

          %Node{first_public_key: _},
          %ReplicateTransaction{
            transaction: %Transaction{address: "@Alice1"}
          },
          _ ->
            {:ok, %Ok{}}
        end
      )

      assert_receive {:aggreate_write, aggregate}
    end
  end
end
