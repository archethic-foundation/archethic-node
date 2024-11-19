defmodule Archethic.P2P.Message.ReplicationSignatureDoneTest do
  @moduledoc false
  use ArchethicCase
  import ArchethicCase

  alias Archethic.P2P.Message.ReplicationSignatureDone
  alias Archethic.TransactionChain.Transaction.ProofOfReplication.Signature

  test "serialize/deserialize" do
    sig = %Signature{
      signature: :crypto.strong_rand_bytes(96),
      node_mining_key: random_public_key(:bls),
      node_public_key: random_public_key()
    }

    msg = %ReplicationSignatureDone{
      address: random_address(),
      replication_signature: sig
    }

    assert {^msg, <<>>} =
             msg
             |> ReplicationSignatureDone.serialize()
             |> ReplicationSignatureDone.deserialize()
  end
end
