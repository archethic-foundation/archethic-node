defmodule Uniris.BeaconChain.SubsetTest do
  use UnirisCase, async: false

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.NodeInfo
  alias Uniris.BeaconChain.Slot.TransactionInfo

  alias Uniris.BeaconChain.Subset
  alias Uniris.BeaconChain.Subset.SlotRegistry

  alias Uniris.TransactionChain.Transaction

  alias Uniris.Utils

  setup do
    pid = start_supervised!({Subset, subset: <<0>>})
    {:ok, subset: <<0>>, pid: pid}
  end

  test "add_transaction_info/2 should publish a transaction into the next beacon block", %{
    subset: subset,
    pid: pid
  } do
    tx_time = DateTime.utc_now()
    tx_address = :crypto.strong_rand_bytes(32)

    Subset.add_transaction_info(subset, %TransactionInfo{
      address: tx_address,
      timestamp: tx_time,
      type: :node
    })

    assert %{
             slot_registry: %SlotRegistry{
               current_slot: %Slot{transactions: [%TransactionInfo{address: ^tx_address}]}
             }
           } = :sys.get_state(pid)
  end

  test "add_node_info/2 should insert node info in the beacon slot", %{subset: subset, pid: pid} do
    public_key = :crypto.strong_rand_bytes(32)
    :ok = Subset.add_node_info(subset, %NodeInfo{public_key: public_key, ready?: true})

    assert %{
             slot_registry: %SlotRegistry{
               current_slot: %Slot{nodes: [%NodeInfo{public_key: ^public_key}]}
             }
           } = :sys.get_state(pid)
  end

  test "new slot is created when receive a :create_slot message", %{subset: subset, pid: pid} do
    tx_time = DateTime.utc_now()
    tx_address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    Subset.add_transaction_info(subset, %TransactionInfo{
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

    Subset.add_node_info(subset, %NodeInfo{
      public_key: public_key,
      timestamp: ready_time
    })

    send(pid, {:create_slot, DateTime.utc_now()})

    %{slot_registry: %SlotRegistry{slots: slots, current_slot: %Slot{}}} = :sys.get_state(pid)

    [
      %Transaction{
        data: %{
          content: tx_content
        }
      }
    ] = Map.values(slots)

    assert {%Slot{
              transactions: [
                %TransactionInfo{
                  address: ^tx_address
                }
              ],
              nodes: [
                %NodeInfo{
                  public_key: ^public_key
                }
              ]
            }, _} = Slot.deserialize(tx_content)
  end

  test "missing_slots/2 should retrieve the previous beacon slots after the given date", %{
    subset: subset,
    pid: pid
  } do
    tx_time = DateTime.utc_now()
    tx_address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    Subset.add_transaction_info(subset, %TransactionInfo{
      address: tx_address,
      timestamp: tx_time,
      type: :keychain
    })

    public_key = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    Subset.add_node_info(subset, %NodeInfo{
      public_key: public_key,
      timestamp: tx_time,
      ready?: true
    })

    send(pid, {:create_slot, DateTime.utc_now() |> DateTime.add(60)})

    slots = Subset.missing_slots(subset, DateTime.utc_now())
    assert length(slots) == 1

    assert %Slot{
             transactions: [
               %TransactionInfo{
                 address: tx_address,
                 timestamp: Utils.truncate_datetime(tx_time),
                 type: :keychain
               }
             ],
             nodes: [
               %NodeInfo{
                 public_key: public_key,
                 ready?: true,
                 timestamp: Utils.truncate_datetime(tx_time)
               }
             ]
           } == List.first(slots)
  end
end
