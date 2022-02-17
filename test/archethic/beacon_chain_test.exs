defmodule ArchEthic.BeaconChainTest do
  use ArchEthicCase

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.Slot
  alias ArchEthic.BeaconChain.Slot.EndOfNodeSync
  alias ArchEthic.BeaconChain.Slot.TransactionSummary
  alias ArchEthic.BeaconChain.SlotTimer
  alias ArchEthic.BeaconChain.Subset
  alias ArchEthic.BeaconChain.Subset.SummaryCache
  alias ArchEthic.BeaconChain.SubsetRegistry
  alias ArchEthic.BeaconChain.SummaryTimer

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.TransactionData

  alias ArchEthic.Utils

  doctest ArchEthic.BeaconChain

  setup do
    start_supervised!({SlotTimer, interval: "0 0 * * * *"})
    Enum.map(BeaconChain.list_subsets(), &start_supervised({Subset, subset: &1}, id: &1))
    Enum.each(BeaconChain.list_subsets(), &Subset.start_link(subset: &1))
    :ok
  end

  test "all_subsets/0 should return 256 subsets" do
    assert Enum.map(0..255, &:binary.encode_unsigned(&1)) == BeaconChain.list_subsets()
  end

  test "summary_transaction_address/2 should return a address using the storage nonce a subset and a date" do
    assert <<0, 0, 141, 146, 109, 188, 197, 248, 255, 123, 14, 172, 53, 198, 233, 233, 205, 180,
             221, 95, 244, 203, 222, 149, 194, 205, 73, 214, 9, 207, 197, 55, 59,
             182>> = BeaconChain.summary_transaction_address(<<1>>, ~U[2021-01-13 00:00:00Z])

    assert <<0, 0, 25, 97, 166, 116, 204, 210, 75, 152, 0, 193, 90, 253, 228, 140, 38, 248, 49,
             160, 210, 186, 181, 32, 203, 157, 110, 67, 255, 181, 80, 96, 160,
             239>> = BeaconChain.summary_transaction_address(<<1>>, ~U[2021-01-14 00:00:00Z])
  end

  test "add_transaction_summary/1 should register a transaction inside a subset" do
    address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    assert :ok =
             BeaconChain.add_transaction_summary(%Transaction{
               address: address,
               type: :transfer,
               validation_stamp: %ValidationStamp{
                 timestamp: DateTime.utc_now()
               }
             })

    subset = BeaconChain.subset_from_address(address)
    [{pid, _}] = Registry.lookup(SubsetRegistry, subset)

    %{current_slot: %Slot{transaction_summaries: [%TransactionSummary{address: ^address}]}} =
      :sys.get_state(pid)
  end

  test "add_end_of_node_sync/2 should register a end of synchronization inside a subset" do
    public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    assert :ok = BeaconChain.add_end_of_node_sync(public_key, DateTime.utc_now())

    <<_::8, _::8, subset::binary-size(1), _::binary>> = public_key
    [{pid, _}] = Registry.lookup(SubsetRegistry, subset)

    %{
      current_slot: %Slot{end_of_node_synchronizations: [%EndOfNodeSync{public_key: ^public_key}]}
    } = :sys.get_state(pid)
  end

  describe "load_transaction/1 for beacon transaction" do
    test "should fetch the transaction chain from the beacon involved nodes" do
      SummaryTimer.start_link(interval: "0 0 * * * *")

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
        last_public_key: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-10)
      })

      tx = %Transaction{
        address: Crypto.derive_beacon_chain_address(<<0>>, DateTime.utc_now()),
        type: :beacon,
        data: %TransactionData{
          content:
            %Slot{subset: <<0>>, slot_time: DateTime.utc_now(), transaction_summaries: []}
            |> Slot.serialize()
            |> Utils.wrap_binary()
        },
        validation_stamp: %ValidationStamp{
          timestamp: DateTime.utc_now()
        }
      }

      assert :ok = BeaconChain.load_transaction(tx)

      assert [%Slot{subset: <<0>>}] = SummaryCache.pop_slots(<<0>>)
    end
  end
end
