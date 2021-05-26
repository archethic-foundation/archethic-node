defmodule Uniris.BeaconChain.SubsetTest do
  use UnirisCase, async: false

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.SummaryTimer

  alias Uniris.BeaconChain.Subset

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Message.ReplicateTransaction
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData

  alias Uniris.Utils

  import Mox

  setup do
    start_supervised!({SummaryTimer, interval: "0 0 * * * *"})
    start_supervised!({SlotTimer, interval: "0 * * * * *"})
    pid = start_supervised!({Subset, subset: <<0>>})
    {:ok, subset: <<0>>, pid: pid}
  end

  test "add_transaction_summary/2 should publish a transaction into the next beacon block", %{
    subset: subset,
    pid: pid
  } do
    tx_time = DateTime.utc_now()
    tx_address = :crypto.strong_rand_bytes(32)

    Subset.add_transaction_summary(subset, %TransactionSummary{
      address: tx_address,
      timestamp: tx_time,
      type: :node
    })

    assert %{
             current_slot: %Slot{
               transaction_summaries: [%TransactionSummary{address: ^tx_address}]
             }
           } = :sys.get_state(pid)
  end

  test "add_end_of_node_sync/2 should insert end of node synchronization in the beacon slot", %{
    subset: subset,
    pid: pid
  } do
    public_key = :crypto.strong_rand_bytes(32)

    :ok = Subset.add_end_of_node_sync(subset, %EndOfNodeSync{public_key: public_key})

    assert %{
             current_slot: %Slot{
               end_of_node_synchronizations: [%EndOfNodeSync{public_key: ^public_key}]
             }
           } = :sys.get_state(pid)
  end

  test "new slot is created when receive a :create_slot message", %{subset: subset, pid: pid} do
    tx_time = DateTime.utc_now()
    tx_address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.first_node_public_key(),
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
      last_public_key: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    Subset.add_transaction_summary(subset, %TransactionSummary{
      address: tx_address,
      timestamp: tx_time,
      type: :keychain,
      movements_addresses: [
        <<0, 109, 2, 63, 124, 238, 101, 213, 214, 64, 58, 218, 10, 35, 62, 202, 12, 64, 11, 232,
          210, 105, 102, 193, 193, 24, 54, 42, 200, 226, 13, 38, 69>>,
        <<0, 8, 253, 201, 142, 182, 78, 169, 132, 29, 19, 74, 3, 142, 207, 219, 127, 147, 40, 24,
          44, 170, 214, 171, 224, 29, 177, 205, 226, 88, 62, 248, 84>>
      ]
    })

    public_key = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    ready_time = DateTime.utc_now()

    Subset.add_end_of_node_sync(subset, %EndOfNodeSync{
      public_key: public_key,
      timestamp: ready_time
    })

    me = self()

    MockClient
    |> expect(:send_message, fn _, %ReplicateTransaction{transaction: tx} ->
      send(me, {:beacon_tx, tx})
      {:ok, %Ok{}}
    end)

    send(pid, {:create_slot, DateTime.utc_now()})

    assert_receive {:beacon_tx,
                    %Transaction{type: :beacon, data: %TransactionData{content: content}}}

    assert {%Slot{transaction_summaries: [%TransactionSummary{address: ^tx_address}]}, _} =
             Slot.deserialize(content)
  end

  test "new summary is created when the slot time is the summary time", %{
    subset: subset,
    pid: pid
  } do
    tx_time = DateTime.utc_now()
    tx_address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.first_node_public_key(),
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: ~U[2020-09-01 00:00:00Z]
    })

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
      last_public_key: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: ~U[2020-09-01 00:00:00Z]
    })

    tx_summary = %TransactionSummary{
      address: tx_address,
      timestamp: tx_time,
      type: :keychain,
      movements_addresses: [
        <<0, 109, 2, 63, 124, 238, 101, 213, 214, 64, 58, 218, 10, 35, 62, 202, 12, 64, 11, 232,
          210, 105, 102, 193, 193, 24, 54, 42, 200, 226, 13, 38, 69>>,
        <<0, 8, 253, 201, 142, 182, 78, 169, 132, 29, 19, 74, 3, 142, 207, 219, 127, 147, 40, 24,
          44, 170, 214, 171, 224, 29, 177, 205, 226, 88, 62, 248, 84>>
      ]
    }

    Subset.add_transaction_summary(subset, tx_summary)

    me = self()

    MockClient
    |> expect(:send_message, fn _, %ReplicateTransaction{} ->
      {:ok, %Ok{}}
    end)

    beacon_addr = Crypto.derive_beacon_chain_address(subset, ~U[2020-10-01 00:00:00Z])

    MockDB
    |> stub(:write_transaction_chain, fn chain ->
      send(me, {:chain, chain})
      :ok
    end)
    |> stub(:get_transaction_chain, fn address, _ ->
      case address do
        ^beacon_addr ->
          [
            %Transaction{
              address: address,
              type: :beacon,
              data: %TransactionData{
                content:
                  %Slot{
                    subset: subset,
                    slot_time: ~U[2020-10-01 00:00:00Z],
                    transaction_summaries: [tx_summary],
                    p2p_view: %{availabilities: <<1::1>>, network_stats: [%{latency: 10}]}
                  }
                  |> Slot.serialize()
                  |> Utils.wrap_binary()
              },
              validation_stamp: %ValidationStamp{
                timestamp: ~U[2020-10-01 00:00:00Z]
              }
            }
          ]

        _ ->
          []
      end
    end)

    send(pid, {:create_slot, ~U[2020-10-01 00:00:00Z]})
    Process.sleep(500)

    assert_receive {:chain, beacon_chain1}
    assert Enum.count(beacon_chain1) == 1

    assert [%Transaction{type: :beacon}] = Enum.to_list(beacon_chain1)

    assert_receive {:chain, beacon_chain2}
    assert Enum.count(beacon_chain2) == 2

    assert [%Transaction{type: :beacon_summary}, %Transaction{type: :beacon}] =
             Enum.to_list(beacon_chain2)
  end
end
