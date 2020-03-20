defmodule UnirisSync.BeaconTest do
  use ExUnit.Case

  alias UnirisCrypto, as: Crypto
  alias UnirisSync.Beacon
  alias UnirisSync.Beacon.Subset, as: BeaconSubset
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.Data

  @beacon_slot_interval 1000

  setup do
    Crypto.add_origin_seed("origin_seed")
    Enum.each(Beacon.all_subsets(), fn subset ->
      BeaconSubset.start_link(subset: subset, slot_interval: @beacon_slot_interval, startup_date: DateTime.utc_now())
    end)
    :ok
  end

  test "add_transaction/2 should publish a transaction into the next beacon block" do
    time = get_time()
    address = :crypto.strong_rand_bytes(32)
    BeaconSubset.add_transaction(address, get_time())
    [{pid, _}] = Registry.lookup(UnirisSync.BeaconSubsetRegistry, :binary.part(address, 1, 1))
    %{buffered_transactions: txs} = :sys.get_state(pid)

    assert txs == [
             {address, time}
           ]
  end

  test "new block is created after 1000 ms" do
    tx_time = get_time()
    tx_address = :crypto.strong_rand_bytes(32)
    BeaconSubset.add_transaction(tx_address, tx_time)
    [{pid, _}] = Registry.lookup(UnirisSync.BeaconSubsetRegistry, :binary.part(tx_address, 1, 1))

    Process.sleep(@beacon_slot_interval)

    slot_time = get_time() - 1
    %{slots: slots} = :sys.get_state(pid)

    %Transaction{
      data: %Data{
        content: tx_content
      }
    } = Map.get(slots, slot_time)

    assert tx_content == "#{tx_time} - #{Base.encode16(tx_address)}"
  end

  defp get_time(), do: DateTime.utc_now() |> DateTime.to_unix()
end
