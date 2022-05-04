defmodule Archethic.BeaconChainTest do
  use ArchethicCase

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Slot.EndOfNodeSync
  alias Archethic.BeaconChain.SlotTimer
  alias Archethic.BeaconChain.Subset
  alias Archethic.BeaconChain.Subset.SummaryCache
  alias Archethic.BeaconChain.SubsetRegistry
  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Utils

  doctest Archethic.BeaconChain

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
    assert <<0, 0, 126, 16, 248, 223, 156, 176, 229, 102, 1, 100, 203, 172, 176, 243, 188, 41, 20,
             170, 58, 159, 173, 181, 185, 11, 231, 174, 223, 115, 196, 88, 243,
             197>> = BeaconChain.summary_transaction_address(<<1>>, ~U[2021-01-13 00:00:00Z])

    assert <<0, 0, 68, 143, 226, 144, 77, 189, 180, 194, 80, 63, 131, 127, 130, 140, 137, 97, 76,
             39, 74, 19, 34, 182, 174, 179, 89, 117, 149, 203, 58, 89, 67,
             68>> = BeaconChain.summary_transaction_address(<<1>>, ~U[2021-01-14 00:00:00Z])
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
            %Slot{subset: <<0>>, slot_time: DateTime.utc_now(), transaction_attestations: []}
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
