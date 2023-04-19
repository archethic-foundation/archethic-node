defmodule Archethic.SelfRepairTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.P2P.Client.DefaultImpl

  alias Archethic.Crypto

  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetNextAddresses

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.SelfRepair

  import Mox

  setup do
    start_supervised!({SummaryTimer, interval: "0 0 * * *"})

    :ok
  end

  test "update_last_address/1 should request missing addresses and add them in DB" do
    node = %Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      geo_patch: "AAA",
      authorized?: true,
      authorization_date: ~U[2022-11-27 00:00:00Z],
      available?: true,
      availability_history: <<1::1>>
    }

    me = self()

    MockDB
    |> expect(:get_last_chain_address, fn "Alice2" -> {"Alice2", ~U[2022-11-27 00:10:00Z]} end)
    |> expect(:get_transaction, fn "Alice2", _, _ ->
      {:ok, %Transaction{validation_stamp: %ValidationStamp{timestamp: ~U[2022-11-27 00:10:00Z]}}}
    end)
    |> expect(:get_genesis_address, 2, fn "Alice2" -> "Alice0" end)
    |> expect(:list_chain_addresses, fn "Alice0" ->
      [
        {"Alice1", ~U[2022-11-27 00:09:00Z]},
        {"Alice2", ~U[2022-11-27 00:10:00Z]},
        {"Alice3", ~U[2022-11-27 00:11:00Z]},
        {"Alice4", ~U[2022-11-27 00:12:00Z]}
      ]
    end)
    |> expect(:add_last_transaction_address, 2, fn
      "Alice0", "Alice3", ~U[2022-11-27 00:11:00Z] ->
        send(me, :add_alice3)

      "Alice0", "Alice4", ~U[2022-11-27 00:12:00Z] ->
        send(me, :add_alice4)
    end)

    MockClient
    |> expect(:send_message, fn node, msg = %GetNextAddresses{address: "Alice2"}, timeout ->
      send(me, :get_next_addresses)
      DefaultImpl.send_message(node, msg, timeout)
    end)

    SelfRepair.update_last_address("Alice2", [node])

    assert_receive :get_next_addresses
    assert_receive :add_alice3
    assert_receive :add_alice4
  end
end
