defmodule UnirisCore.BeaconSubsetTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.BeaconSubset
  alias UnirisCore.BeaconSlot
  alias UnirisCore.BeaconSlot.TransactionInfo
  alias UnirisCore.Transaction

  test "add_transaction_info/2 should publish a transaction into the next beacon block" do
    tx_time = get_time()
    tx_address = :crypto.strong_rand_bytes(32)
    subset = :binary.part(tx_address, 1, 1)

    {:ok, pid} = BeaconSubset.start_link(subset: subset, slot_interval: 1000)

    BeaconSubset.add_transaction_info(subset, %TransactionInfo{
      address: tx_address,
      timestamp: tx_time
    })

    %{current_slot: %BeaconSlot{transactions: txs}} = :sys.get_state(pid)

    assert txs == [
             %TransactionInfo{address: tx_address, timestamp: tx_time}
           ]
  end

  test "new slot is created when receive a :create_slot message" do
    tx_time = get_time()
    tx_address = :crypto.strong_rand_bytes(32)
    subset = :binary.part(tx_address, 1, 1)

    {:ok, pid} = BeaconSubset.start_link(subset: subset, slot_interval: 1000)

    BeaconSubset.add_transaction_info(subset, %TransactionInfo{
      address: tx_address,
      timestamp: tx_time,
      type: :keychain
    })

    send(pid, :create_slot)

    slot_time = get_time()
    %{slots: slots} = :sys.get_state(pid)

    %Transaction{
      data: %{
        content: tx_content
      }
    } = Map.get(slots, DateTime.to_unix(slot_time))

    assert tx_content == "T - 1 - #{DateTime.to_unix(tx_time)} - #{Base.encode16(tx_address)}"
  end

  defp get_time(), do: DateTime.utc_now()
end
