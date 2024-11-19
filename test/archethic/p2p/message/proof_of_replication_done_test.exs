defmodule Archethic.P2P.Message.ProofOfReplicationDoneTest do
  @moduledoc false
  use ArchethicCase
  import ArchethicCase

  alias Archethic.P2P.Message.ProofOfReplicationDone
  alias Archethic.TransactionChain.Transaction.ProofOfReplication

  test "serialize/deserialize" do
    proof = %ProofOfReplication{
      signature: :crypto.strong_rand_bytes(96),
      nodes_bitmask: <<0::5, -1::3, 0::2>>
    }

    msg = %ProofOfReplicationDone{address: random_address(), proof_of_replication: proof}

    assert {^msg, <<>>} =
             msg
             |> ProofOfReplicationDone.serialize()
             |> ProofOfReplicationDone.deserialize()
  end
end
