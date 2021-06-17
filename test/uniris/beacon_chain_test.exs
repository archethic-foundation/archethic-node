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
  alias Uniris.P2P.Message.GetTransactionChain
  alias Uniris.P2P.Message.TransactionList
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData

  alias Uniris.Utils

  doctest Uniris.BeaconChain

  import Mox

  setup do
    start_supervised!({SlotTimer, interval: "0 0 * * * *"})
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
            available?: true,
            authorized?: true,
            authorization_date: date_ref
          },
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            first_public_key: "key2",
            last_public_key: "key2",
            geo_patch: "AAA",
            available?: true,
            authorized?: true,
            authorization_date: date_ref
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
            available?: true,
            authorized?: true,
            authorization_date: date_ref
          },
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            first_public_key: "key2",
            last_public_key: "key2",
            geo_patch: "AAA",
            available?: true,
            authorized?: true,
            authorization_date: date_ref
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
    assert <<0, 141, 146, 109, 188, 197, 248, 255, 123, 14, 172, 53, 198, 233, 233, 205, 180, 221,
             95, 244, 203, 222, 149, 194, 205, 73, 214, 9, 207, 197, 55, 59,
             182>> = BeaconChain.summary_transaction_address(<<1>>, ~U[2021-01-13 00:00:00Z])

    assert <<0, 25, 97, 166, 116, 204, 210, 75, 152, 0, 193, 90, 253, 228, 140, 38, 248, 49, 160,
             210, 186, 181, 32, 203, 157, 110, 67, 255, 181, 80, 96, 160,
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
    public_key = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    assert :ok = BeaconChain.add_end_of_node_sync(public_key, DateTime.utc_now())

    subset = BeaconChain.subset_from_address(public_key)
    [{pid, _}] = Registry.lookup(SubsetRegistry, subset)

    %{
      current_slot: %Slot{end_of_node_synchronizations: [%EndOfNodeSync{public_key: ^public_key}]}
    } = :sys.get_state(pid)
  end

  describe "load_transaction/1 for beacon transaction" do
    test "should fetch the transaction chain from the beacon involved nodes" do
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

      MockClient
      |> expect(:send_message, fn _, %GetTransactionChain{} ->
        {:ok,
         %TransactionList{
           transactions: []
         }}
      end)

      me = self()

      MockDB
      |> expect(:write_transaction_chain, fn chain ->
        send(me, {:chain, chain})
        :ok
      end)

      assert :ok = BeaconChain.load_transaction(tx)

      assert_receive {:chain, chain}
      assert Enum.count(chain) == 1
    end
  end

  # describe "register_slot/1" do
  #   setup do
  #     start_supervised!({SummaryTimer, interval: "0 0 0 * * *"})
  #     :ok
  #   end

  #   test "should return an error when the node is not in expected summary pool" do
  #     assert {:error, :not_storage_node} =
  #              BeaconChain.register_slot(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})
  #   end

  #   test "should return an error when the previous hash is the not a valid one" do
  #     P2P.add_and_connect_node(%Node{
  #       ip: {127, 0, 0, 1},
  #       port: 3000,
  #       first_public_key: Crypto.first_node_public_key(),
  #       last_public_key: Crypto.first_node_public_key(),
  #       available?: true,
  #       geo_patch: "AAA",
  #       authorized?: true,
  #       authorization_date: DateTime.utc_now() |> DateTime.add(-1)
  #     })

  #     assert {:error, :invalid_previous_hash} =
  #              BeaconChain.register_slot(%Slot{
  #                subset: <<0>>,
  #                slot_time: DateTime.utc_now(),
  #                previous_hash: :crypto.strong_rand_bytes(32)
  #              })
  #   end

  #   test "should return an error when the signatures are not valid" do
  #     P2P.add_and_connect_node(%Node{
  #       ip: {127, 0, 0, 1},
  #       port: 3000,
  #       first_public_key: Crypto.first_node_public_key(),
  #       last_public_key: Crypto.first_node_public_key(),
  #       available?: true,
  #       geo_patch: "AAA",
  #       authorized?: true,
  #       authorization_date: DateTime.utc_now() |> DateTime.add(-1)
  #     })

  #     assert {:error, :invalid_signatures} =
  #              BeaconChain.register_slot(%Slot{
  #                subset: <<0>>,
  #                slot_time: DateTime.utc_now(),
  #                validation_signatures: [{0, :crypto.strong_rand_bytes(32)}]
  #              })
  #   end

  #   test "should insert the slot" do
  #     P2P.add_and_connect_node(%Node{
  #       ip: {127, 0, 0, 1},
  #       port: 3000,
  #       first_public_key: Crypto.first_node_public_key(),
  #       last_public_key: Crypto.first_node_public_key(),
  #       available?: true,
  #       geo_patch: "AAA",
  #       authorized?: true,
  #       authorization_date: ~U[2021-01-20 15:17:00Z]
  #     })

  #     slot = %Slot{subset: <<0>>, slot_time: ~U[2021-01-22 15:17:00Z]}

  #     sig1 =
  #       slot
  #       |> Slot.to_pending()
  #       |> Slot.serialize()
  #       |> Crypto.sign_with_node_key(0)

  #     me = self()

  #     MockDB
  #     |> expect(:register_beacon_slot, fn slot ->
  #       send(me, {:slot, slot})
  #       :ok
  #     end)

  #     assert :ok = BeaconChain.register_slot(%{slot | validation_signatures: [{0, sig1}]})
  #     assert_receive {:slot, %Slot{subset: <<0>>}}
  #   end

  #   test "should not insert the slot if a slot is already persisted and no more signatures" do
  #     P2P.add_and_connect_node(%Node{
  #       ip: {127, 0, 0, 1},
  #       port: 3000,
  #       first_public_key: Crypto.first_node_public_key(),
  #       last_public_key: Crypto.first_node_public_key(),
  #       available?: true,
  #       geo_patch: "AAA",
  #       authorized?: true,
  #       authorization_date: ~U[2021-01-20 15:17:00Z]
  #     })

  #     slot = %Slot{subset: <<0>>, slot_time: ~U[2021-01-22 15:17:00Z]}

  #     sig1 =
  #       slot
  #       |> Slot.to_pending()
  #       |> Slot.serialize()
  #       |> Crypto.sign_with_node_key(0)

  #     MockDB
  #     |> stub(:get_beacon_slot, fn
  #       _, ~U[2021-01-22 15:17:00Z] -> {:ok, slot}
  #       _, _ -> {:error, :not_found}
  #     end)

  #     assert :ok = BeaconChain.register_slot(%{slot | validation_signatures: %{0 => sig1}})
  #   end

  #   test "should not insert the slot if the receiving node has more signature than the previous one" do
  #     P2P.add_and_connect_node(%Node{
  #       ip: {127, 0, 0, 1},
  #       port: 3000,
  #       first_public_key: Crypto.first_node_public_key(),
  #       last_public_key: Crypto.first_node_public_key(),
  #       available?: true,
  #       geo_patch: "AAA",
  #       authorized?: true,
  #       authorization_date: ~U[2021-01-20 15:17:00Z]
  #     })

  #     P2P.add_and_connect_node(%Node{
  #       ip: {127, 0, 0, 1},
  #       port: 3000,
  #       first_public_key: Crypto.node_public_key(1),
  #       last_public_key: Crypto.node_public_key(1),
  #       available?: true,
  #       geo_patch: "AAA",
  #       authorized?: true,
  #       authorization_date: ~U[2021-01-20 15:17:00Z]
  #     })

  #     slot = %Slot{subset: <<0>>, slot_time: ~U[2021-01-22 15:17:00Z]}

  #     sig1 =
  #       slot
  #       |> Slot.to_pending()
  #       |> Slot.serialize()
  #       |> Crypto.sign_with_node_key(0)

  #     me = self()

  #     MockDB
  #     |> stub(:get_beacon_slot, fn
  #       _, ~U[2021-01-22 15:17:00Z] -> {:ok, slot}
  #       _, _ -> {:error, :not_found}
  #     end)
  #     |> expect(:register_beacon_slot, fn slot ->
  #       send(me, {:slot, slot})
  #       :ok
  #     end)

  #     sig2 =
  #       slot
  #       |> Slot.to_pending()
  #       |> Slot.serialize()
  #       |> Crypto.sign_with_node_key(1)

  #     assert :ok =
  #              BeaconChain.register_slot(%{slot | validation_signatures: %{0 => sig2, 1 => sig1}})

  #     assert_receive {:slot, %Slot{validation_signatures: %{}}}
  #   end
  # end
end
