defmodule Uniris.BeaconChainTest do
  use UnirisCase

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.Subset
  alias Uniris.BeaconChain.SubsetRegistry
  alias Uniris.BeaconChain.SummaryTimer

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp

  doctest Uniris.BeaconChain

  import Mox

  setup do
    Enum.map(BeaconChain.list_subsets(), &start_supervised({Subset, subset: &1}, id: &1))
    Enum.each(BeaconChain.list_subsets(), &Subset.start_link(subset: &1))
    :ok
  end

  describe "get_summary_pools/2" do
    setup do
      start_supervised!({SummaryTimer, interval: "0 0 0 * * *"})
      :ok
    end

    test "with 1 day off" do
      date_ref = DateTime.utc_now() |> DateTime.add(-86_400)

      pools =
        BeaconChain.get_summary_pools(date_ref, [
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            first_public_key: "key1",
            last_public_key: "key1",
            geo_patch: "AAA",
            available?: true
          },
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            first_public_key: "key2",
            last_public_key: "key2",
            geo_patch: "AAA",
            available?: true
          }
        ])

      assert Enum.all?(pools, fn {_, nodes_by_summary} ->
               assert length(nodes_by_summary) == 1
               assert Enum.all?(nodes_by_summary, &(tuple_size(&1) == 2))
             end)
    end

    test "with 10 days off" do
      date_ref = DateTime.utc_now() |> DateTime.add(-86_400 * 10)

      pools =
        BeaconChain.get_summary_pools(date_ref, [
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            first_public_key: "key1",
            last_public_key: "key1",
            geo_patch: "AAA",
            available?: true
          },
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            first_public_key: "key2",
            last_public_key: "key2",
            geo_patch: "AAA",
            available?: true
          }
        ])

      assert Enum.all?(pools, fn {_, nodes_by_summary} ->
               assert length(nodes_by_summary) == 10
               assert Enum.all?(nodes_by_summary, &(tuple_size(&1) == 2))
             end)
    end
  end

  test "all_subsets/0 should return 256 subsets" do
    assert Enum.map(0..255, &:binary.encode_unsigned(&1)) == BeaconChain.list_subsets()
  end

  test "summary_transaction_address/2 should return a address using the storage nonce a subset and a date" do
    assert <<0, 20, 67, 131, 34, 30, 226, 235, 247, 202, 0, 199, 208, 173, 117, 231, 252, 19, 83,
             196, 76, 63, 172, 254, 160, 255, 172, 88, 217, 246, 47, 204,
             235>> = BeaconChain.summary_transaction_address(<<1>>, ~U[2021-01-13 00:00:00Z])

    assert <<0, 96, 30, 212, 152, 62, 254, 106, 56, 26, 32, 23, 61, 242, 173, 246, 138, 17, 19,
             121, 64, 48, 225, 103, 107, 44, 114, 214, 43, 92, 185, 211,
             119>> = BeaconChain.summary_transaction_address(<<1>>, ~U[2021-01-14 00:00:00Z])
  end

  test "add_transaction_summary/1 should register a transaction inside a subset" do
    address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    assert :ok =
             BeaconChain.add_transaction_summary(%Transaction{
               address: address,
               type: :transfer,
               timestamp: DateTime.utc_now(),
               validation_stamp: %ValidationStamp{}
             })

    subset = BeaconChain.subset_from_address(address)
    [{pid, _}] = Registry.lookup(SubsetRegistry, subset)

    %{current_slot: %Slot{transaction_summaries: [%TransactionSummary{address: ^address}]}} =
      :sys.get_state(pid)
  end

  test "add_end_of_node_sync/2 should register a end of synchronization inside a subset" do
    public_key = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    assert :ok = BeaconChain.add_end_of_node_sync(public_key, DateTime.utc_now())

    subset = BeaconChain.subset_from_address(public_key)
    [{pid, _}] = Registry.lookup(SubsetRegistry, subset)

    %{
      current_slot: %Slot{end_of_node_synchronizations: [%EndOfNodeSync{public_key: ^public_key}]}
    } = :sys.get_state(pid)
  end

  describe "register_slot/1" do
    setup do
      start_supervised!({SummaryTimer, interval: "0 0 0 * * *"})
      start_supervised!({SlotTimer, interval: "0 0 * * * *"})
      :ok
    end

    test "should return an error when the node is not in expected summary pool" do
      assert {:error, :not_storage_node} =
               BeaconChain.register_slot(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})
    end

    test "should return an error when the previous hash is the not a valid one" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(0),
        available?: true,
        geo_patch: "AAA",
        enrollment_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      assert {:error, :invalid_previous_hash} =
               BeaconChain.register_slot(%Slot{
                 subset: <<0>>,
                 slot_time: DateTime.utc_now(),
                 previous_hash: :crypto.strong_rand_bytes(32)
               })
    end

    test "should return an error when the signatures are not valid" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(0),
        available?: true,
        geo_patch: "AAA",
        enrollment_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      assert {:error, :invalid_signatures} =
               BeaconChain.register_slot(%Slot{
                 subset: <<0>>,
                 slot_time: DateTime.utc_now(),
                 validation_signatures: [{0, :crypto.strong_rand_bytes(32)}]
               })
    end

    test "should insert the slot" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(0),
        available?: true,
        geo_patch: "AAA",
        enrollment_date: ~U[2021-01-20 15:17:00Z]
      })

      slot = %Slot{subset: <<0>>, slot_time: ~U[2021-01-22 15:17:00Z]}

      sig1 =
        slot
        |> Slot.digest()
        |> Crypto.sign_with_node_key(0)

      me = self()

      MockDB
      |> expect(:register_beacon_slot, fn slot ->
        send(me, {:slot, slot})
        :ok
      end)

      assert :ok = BeaconChain.register_slot(%{slot | validation_signatures: [{0, sig1}]})
      assert_receive {:slot, %Slot{subset: <<0>>}}
    end

    test "should not insert the slot if a slot is already persisted and no more signatures" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(0),
        available?: true,
        geo_patch: "AAA",
        enrollment_date: ~U[2021-01-20 15:17:00Z]
      })

      slot = %Slot{subset: <<0>>, slot_time: ~U[2021-01-22 15:17:00Z]}

      sig1 =
        slot
        |> Slot.digest()
        |> Crypto.sign_with_node_key(0)

      MockDB
      |> stub(:get_beacon_slot, fn
        _, ~U[2021-01-22 15:17:00Z] -> {:ok, slot}
        _, _ -> {:error, :not_found}
      end)

      assert :ok = BeaconChain.register_slot(%{slot | validation_signatures: %{0 => sig1}})
    end

    test "should not insert the slot if the receiving node has more signature than the previous one" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(0),
        available?: true,
        geo_patch: "AAA",
        enrollment_date: ~U[2021-01-20 15:17:00Z]
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(1),
        last_public_key: Crypto.node_public_key(1),
        available?: true,
        geo_patch: "AAA",
        enrollment_date: ~U[2021-01-20 15:17:00Z]
      })

      slot = %Slot{subset: <<0>>, slot_time: ~U[2021-01-22 15:17:00Z]}

      sig1 =
        slot
        |> Slot.digest()
        |> Crypto.sign_with_node_key(0)

      me = self()

      MockDB
      |> stub(:get_beacon_slot, fn
        _, ~U[2021-01-22 15:17:00Z] -> {:ok, slot}
        _, _ -> {:error, :not_found}
      end)
      |> expect(:register_beacon_slot, fn slot ->
        send(me, {:slot, slot})
        :ok
      end)

      sig2 =
        slot
        |> Slot.digest()
        |> Crypto.sign_with_node_key(1)

      assert :ok =
               BeaconChain.register_slot(%{slot | validation_signatures: %{0 => sig2, 1 => sig1}})

      assert_receive {:slot, %Slot{validation_signatures: %{}}}
    end
  end
end
