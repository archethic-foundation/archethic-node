defmodule UnirisBeacon.SubsetTest do
  use ExUnit.Case

  alias UnirisCrypto, as: Crypto
  alias UnirisBeacon.Subset
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.Data

  @beacon_slot_interval Application.get_env(:uniris_beacon, :slot_interval)

  setup do
    Crypto.add_origin_seed("origin_seed")
    :ok
  end

  test "add_transaction/2 should publish a transaction into the next beacon block" do
    time = get_time()
    address = :crypto.strong_rand_bytes(32)
    Subset.add_transaction(address, get_time())
    [{pid, _}] = Registry.lookup(UnirisBeacon.SubsetRegistry, :binary.part(address, 1, 1))
    %{buffered_transactions: txs} = :sys.get_state(pid)

    assert txs == [
             {address, time}
           ]
  end

  test "new slot is created when receive a :create_slot message" do
    tx_time = get_time()
    tx_address = :crypto.strong_rand_bytes(32)
    Subset.add_transaction(tx_address, tx_time)
    [{pid, _}] = Registry.lookup(UnirisBeacon.SubsetRegistry, :binary.part(tx_address, 1, 1))

    send(pid, :create_slot)

    slot_time = get_time()
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
