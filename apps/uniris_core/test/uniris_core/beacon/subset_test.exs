defmodule UnirisCore.BeaconSubsetTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.BeaconSubset
  alias UnirisCore.BeaconSlot
  alias UnirisCore.BeaconSlot.TransactionInfo
  alias UnirisCore.BeaconSlot.NodeInfo
  alias UnirisCore.Transaction

  setup do
    pid = start_supervised!({BeaconSubset, subset: <<0>>})
    start_supervised!(UnirisCore.Storage.Cache)
    {:ok, subset: <<0>>, pid: pid}
  end

  test "add_transaction_info/2 should publish a transaction into the next beacon block", %{
    subset: subset,
    pid: pid
  } do
    tx_time = DateTime.utc_now()
    tx_address = :crypto.strong_rand_bytes(32)

    BeaconSubset.add_transaction_info(subset, %TransactionInfo{
      address: tx_address,
      timestamp: tx_time,
      type: :node
    })

    assert %{
             current_slot: %BeaconSlot{
               transactions: [
                 %TransactionInfo{address: tx_address, timestamp: tx_time, type: :node}
               ]
             }
           } = :sys.get_state(pid)
  end

  test "add_node_info/2 should insert node info in the beacon slot", %{subset: subset, pid: pid} do
    public_key = :crypto.strong_rand_bytes(32)
    :ok = BeaconSubset.add_node_info(subset, %NodeInfo{public_key: public_key, ready?: true})

    assert %{current_slot: %BeaconSlot{nodes: [%NodeInfo{public_key: public_key, ready?: true}]}} =
             :sys.get_state(pid)
  end

  test "new slot is created when receive a :create_slot message", %{subset: subset, pid: pid} do
    tx_time = DateTime.utc_now()
    tx_address = :crypto.strong_rand_bytes(32)

    BeaconSubset.add_transaction_info(subset, %TransactionInfo{
      address: tx_address,
      timestamp: tx_time,
      type: :keychain
    })

    public_key = :crypto.strong_rand_bytes(32)
    ready_time = DateTime.utc_now()

    BeaconSubset.add_node_info(subset, %NodeInfo{
      public_key: public_key,
      ready?: true,
      timestamp: ready_time
    })

    send(pid, {:create_slot, DateTime.utc_now()})

    %{slots: slots} = :sys.get_state(pid)

    [
      %Transaction{
        data: %{
          content: tx_content
        }
      }
    ] = Map.values(slots)

    assert tx_content ==
             Enum.join(
               [
                 "T - 1 - #{DateTime.to_unix(tx_time)} - #{Base.encode16(tx_address)}",
                 "N - #{Base.encode16(public_key)} - #{DateTime.to_unix(ready_time)} - R"
               ],
               "\n"
             )
  end

  test "previous_slots/2 should retrieve the previous beacon slots after the given date", %{
    subset: subset,
    pid: pid
  } do
    tx_time = DateTime.utc_now()
    tx_address = :crypto.strong_rand_bytes(32)

    BeaconSubset.add_transaction_info(subset, %TransactionInfo{
      address: tx_address,
      timestamp: tx_time,
      type: :keychain
    })

    public_key = :crypto.strong_rand_bytes(32)

    BeaconSubset.add_node_info(subset, %NodeInfo{
      public_key: public_key,
      ready?: true,
      timestamp: DateTime.utc_now()
    })

    send(pid, {:create_slot, DateTime.utc_now() |> DateTime.add(60)})

    slots = BeaconSubset.previous_slots(subset, [DateTime.utc_now()])
    assert length(slots) == 1

    assert %BeaconSlot{
             transactions: [
               %TransactionInfo{
                 address: tx_address,
                 timestamp: tx_time,
                 type: :keychain
               }
             ],
             nodes: [
               %NodeInfo{public_key: public_key, ready?: true}
             ]
           } = List.first(slots)
  end
end
