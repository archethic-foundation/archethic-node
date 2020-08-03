defmodule Uniris.BeaconSubsetTest do
  use UnirisCase, async: false

  alias Uniris.BeaconSlot
  alias Uniris.BeaconSlot.NodeInfo
  alias Uniris.BeaconSlot.TransactionInfo

  alias Uniris.BeaconSubset

  alias Uniris.Transaction

  setup do
    pid = start_supervised!({BeaconSubset, subset: <<0>>})
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
      type: :keychain,
      movements_addresses: [
        <<109, 2, 63, 124, 238, 101, 213, 214, 64, 58, 218, 10, 35, 62, 202, 12, 64, 11, 232, 210,
          105, 102, 193, 193, 24, 54, 42, 200, 226, 13, 38, 69>>,
        <<8, 253, 201, 142, 182, 78, 169, 132, 29, 19, 74, 3, 142, 207, 219, 127, 147, 40, 24, 44,
          170, 214, 171, 224, 29, 177, 205, 226, 88, 62, 248, 84>>
      ]
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
                 "T - 1 - #{DateTime.to_unix(tx_time)} - #{Base.encode16(tx_address)} - 6D023F7CEE65D5D6403ADA0A233ECA0C400BE8D26966C1C118362AC8E20D2645 - 08FDC98EB64EA9841D134A038ECFDB7F9328182CAAD6ABE01DB1CDE2583EF854",
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
