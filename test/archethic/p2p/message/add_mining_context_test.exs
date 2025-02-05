defmodule Archethic.P2P.Message.AddMiningContextTest do
  @moduledoc false
  use ExUnit.Case

  import ArchethicCase

  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.AddMiningContext
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  doctest AddMiningContext

  test "serialization/deserialization" do
    msg = %AddMiningContext{
      address: random_address(),
      utxos_hashes: [],
      validation_node_public_key: random_public_key(),
      chain_storage_nodes_view: <<1::1, 0::1, 0::1, 1::1, 0::1>>,
      beacon_storage_nodes_view: <<0::1, 1::1, 1::1, 1::1>>,
      io_storage_nodes_view: <<0::1, 1::1, 1::1, 1::1>>
    }

    assert ^msg =
             msg
             |> Message.encode()
             |> Message.decode()
             |> elem(0)
  end

  test "serialization/deserialization of utxos_hashes" do
    hash1 =
      %UnspentOutput{
        amount: 1,
        type: {:token, random_address(), 0},
        from: random_address(),
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }
      |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())
      |> VersionedUnspentOutput.hash()

    hash2 =
      %UnspentOutput{
        amount: 2,
        type: {:token, random_address(), 0},
        from: random_address(),
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }
      |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())
      |> VersionedUnspentOutput.hash()

    msg = %AddMiningContext{
      address: random_address(),
      utxos_hashes: [hash1, hash2],
      validation_node_public_key: random_public_key(),
      chain_storage_nodes_view: <<1::1, 0::1, 0::1, 1::1, 0::1>>,
      beacon_storage_nodes_view: <<0::1, 1::1, 1::1, 1::1>>,
      io_storage_nodes_view: <<0::1, 1::1, 1::1, 1::1>>
    }

    ctx =
      msg
      |> Message.encode()
      |> Message.decode()
      |> elem(0)

    # order doesn't matter
    assert 2 = Enum.count(ctx.utxos_hashes)
    assert Enum.member?(ctx.utxos_hashes, hash1)
    assert Enum.member?(ctx.utxos_hashes, hash2)
  end
end
