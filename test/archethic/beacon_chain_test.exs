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

  import Mox

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
    assert <<0, 0, 248, 132, 24, 218, 125, 28, 234, 1, 67, 220, 132, 122, 57, 168, 19, 36, 154,
             81, 148, 222, 244, 124, 19, 175, 134, 199, 110, 21, 100, 49, 181,
             210>> = BeaconChain.summary_transaction_address(<<1>>, ~U[2021-01-13 00:00:00Z])

    assert <<0, 0, 15, 150, 229, 125, 70, 53, 7, 122, 235, 195, 14, 164, 62, 53, 217, 55, 181, 13,
             112, 203, 123, 18, 150, 174, 104, 244, 199, 231, 184, 228, 118,
             40>> = BeaconChain.summary_transaction_address(<<1>>, ~U[2021-01-14 00:00:00Z])
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
      SummaryTimer.start_link([interval: "0 0 * * * *"], [])

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

      MockDB
      |> expect(:write_transaction_at, fn _, _ ->
        :ok
      end)

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
