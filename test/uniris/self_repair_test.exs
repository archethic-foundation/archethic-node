defmodule Uniris.SelfRepairTest do
  use UnirisCase, async: false

  alias Uniris.Bootstrap.NetworkInit

  alias Uniris.BeaconSlot
  alias Uniris.BeaconSlot.TransactionInfo
  alias Uniris.BeaconSlotTimer
  alias Uniris.BeaconSubset
  alias Uniris.BeaconSubsets

  alias Uniris.Crypto

  alias Uniris.Mining.Context

  alias Uniris.P2P
  alias Uniris.P2P.Message.BeaconSlotList
  alias Uniris.P2P.Message.GetBeaconSlots
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Node

  alias Uniris.SelfRepair
  alias Uniris.SharedSecrets

  alias Uniris.Transaction
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionData

  alias Uniris.Utils

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    start_supervised!({BeaconSlotTimer, interval: "* * * * * *", trigger_offset: 0})
    Enum.each(BeaconSubsets.all(), &BeaconSubset.start_link(subset: &1))

    last_sync_date = DateTime.utc_now() |> DateTime.add(-60)

    File.write!(
      Application.app_dir(:uniris, "priv/p2p/last_sync"),
      DateTime.to_unix(last_sync_date) |> Integer.to_string(),
      [:write]
    )

    pid =
      start_supervised!(
        {SelfRepair, interval: "* * * * * *", last_sync_file: "priv/p2p/last_sync"}
      )

    {:ok, %{pid: pid, interval: "* * * * * *"}}
  end

  test "start_sync/2 starts the repair mechanism and download missing transactions" do
    me = self()

    SharedSecrets.add_origin_public_key(:software, Crypto.node_public_key(0))

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: Crypto.node_public_key(0),
      first_public_key: Crypto.node_public_key(0),
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-60),
      enrollment_date: DateTime.utc_now() |> DateTime.add(-60)
    })

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: :crypto.strong_rand_bytes(32),
      first_public_key: :crypto.strong_rand_bytes(32),
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true,
      enrollment_date: DateTime.utc_now() |> DateTime.add(-60)
    })

    tx_alice1 =
      Transaction.new(:transfer, %TransactionData{}, "seed", 0)
      |> NetworkInit.self_validation!(%Context{
        unspent_outputs: [
          %UnspentOutput{
            from: :crypto.strong_rand_bytes(32),
            amount: 10
          }
        ]
      })

    Process.sleep(200)

    tx_alice2 =
      Transaction.new(:transfer, %TransactionData{}, "seed", 1)
      |> NetworkInit.self_validation!(%Context{
        previous_chain: [tx_alice1],
        unspent_outputs: [
          %UnspentOutput{
            from: :crypto.strong_rand_bytes(32),
            amount: 10
          }
        ]
      })

    tx_node1 =
      Transaction.new(:node, %TransactionData{})
      |> NetworkInit.self_validation!()

    MockStorage
    |> stub(:write_transaction_chain, fn chain ->
      send(me, chain)
      :ok
    end)
    |> stub(:get_transaction_chain, fn address ->
      if address == tx_alice1.address do
        [tx_alice1]
      else
        []
      end
    end)

    MockNodeClient
    |> stub(:send_message, fn _, _, msg ->
      case msg do
        %GetBeaconSlots{} ->
          %BeaconSlotList{
            slots: [
              %BeaconSlot{
                transactions: [
                  %TransactionInfo{
                    address: tx_alice2.address,
                    type: :transfer,
                    timestamp: DateTime.utc_now() |> DateTime.add(2)
                  }
                ]
              },
              %BeaconSlot{
                transactions: [
                  %TransactionInfo{
                    address: tx_alice1.address,
                    type: :transfer,
                    timestamp: DateTime.utc_now()
                  },
                  %TransactionInfo{
                    address: tx_node1.address,
                    type: :node,
                    timestamp: DateTime.utc_now()
                  }
                ]
              }
            ]
          }

        %GetTransaction{address: address} ->
          cond do
            address == tx_alice1.address ->
              tx_alice1

            address == tx_alice2.address ->
              tx_alice2

            address == tx_node1.address ->
              tx_node1
          end
      end
    end)

    SelfRepair.start_sync("AAA")
    Process.sleep(1_000)

    assert_receive [%Transaction{type: :node, address: _}], 500

    assert_receive [%Transaction{type: :transfer, address: _}], 500

    assert_received [
                      %Transaction{type: :transfer, address: _},
                      %Transaction{type: :transfer, address: _}
                    ],
                    500

    assert_received :sync_finished

    Process.sleep(200)

    assert DateTime.diff(DateTime.utc_now(), SelfRepair.last_sync_date()) >= 0
  end

  @tag time_based: true
  test "should receive sync message when the timer elapse", %{pid: pid, interval: interval} do
    waiting_time = Utils.time_offset(interval)
    :erlang.trace(pid, true, [:receive])

    SelfRepair.start_sync("AAA", false)

    Process.sleep(waiting_time * 1000)

    {:messages, messages} = :erlang.process_info(self(), :messages)
    assert {:trace, pid, :receive, :sync} in messages
  end
end
