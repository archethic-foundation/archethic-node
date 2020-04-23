defmodule UnirisCore.SelfRepairTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.SelfRepair
  alias UnirisCore.Transaction
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.BeaconSlot
  alias UnirisCore.BeaconSlot.TransactionInfo
  alias UnirisCore.Storage

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    %{
      pid: GenServer.start_link(SelfRepair, repair_interval: 1000)
    }
  end

  test "synchronize/2 starts the repair mechanism and download missing transactions" do
    MockStorage
    |> expect(:get_transaction_chain, fn _ ->
      {:ok,
       [
         %Transaction{
           address: "fake_address",
           timestamp: DateTime.utc_now(),
           type: :transfer,
           data: %{},
           previous_public_key: "",
           previous_signature: "",
           origin_signature: ""
         }
       ]}
    end)

    MockNodeClient
    |> stub(:send_message, fn _, msg ->
      case msg do
        {:get_beacon_slots, _subset, _last_sync_data} ->
          [%BeaconSlot{transactions: [%TransactionInfo{address: "fake_address"}]}]

        {:get_transaction_chain, _} ->
          {:ok,
           [
             %Transaction{
               address: "fake_address",
               timestamp: DateTime.utc_now(),
               type: :transfer,
               data: %{},
               previous_public_key: "",
               previous_signature: "",
               origin_signature: ""
             }
           ]}
      end
    end)

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: "key",
      first_public_key: "key",
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      availability: 1,
      authorized?: true
    })

    SelfRepair.synchronize(DateTime.utc_now(), "AAA")
    assert {:ok, _} = Storage.get_transaction_chain("fake_address")
  end
end
