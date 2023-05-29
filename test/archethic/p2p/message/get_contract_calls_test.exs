defmodule Archethic.P2P.Message.GetContractCallsTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.Contracts.TransactionLookup
  alias Archethic.Crypto
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.GetContractCalls
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.TransactionChain.Transaction

  import Mox

  doctest GetContractCalls

  test "should serialize/deserialize properly" do
    msg = %GetContractCalls{
      address: <<0::16, :crypto.strong_rand_bytes(32)::binary>>,
      before: DateTime.utc_now() |> DateTime.truncate(:millisecond)
    }

    assert msg ==
             msg
             |> Message.encode()
             |> Message.decode()
             |> elem(0)
  end

  test "process/2 should work" do
    contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

    msg = %GetContractCalls{
      address: contract_address,
      before: DateTime.utc_now() |> DateTime.add(10)
    }

    tx1 = %Transaction{address: <<0::16, :crypto.strong_rand_bytes(32)::binary>>}
    tx2 = %Transaction{address: <<0::16, :crypto.strong_rand_bytes(32)::binary>>}
    tx1_address = tx1.address
    tx2_address = tx2.address

    TransactionLookup.add_contract_transaction(
      contract_address,
      tx1.address,
      DateTime.utc_now(),
      ArchethicCase.current_protocol_version()
    )

    TransactionLookup.add_contract_transaction(
      contract_address,
      tx2.address,
      DateTime.utc_now(),
      ArchethicCase.current_protocol_version()
    )

    MockDB
    |> expect(:get_transaction, fn ^tx1_address, _, _ ->
      {:ok, tx1}
    end)
    |> expect(:get_transaction, fn ^tx2_address, _, _ ->
      {:ok, tx2}
    end)

    # asserts
    assert %TransactionList{transactions: [^tx1, ^tx2]} =
             GetContractCalls.process(msg, Crypto.first_node_public_key())
  end
end
