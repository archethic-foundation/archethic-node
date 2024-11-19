defmodule Archethic.P2P.Message.RequestReplicationSignatureTest do
  @moduledoc false
  use ArchethicCase
  import ArchethicCase

  alias Archethic.P2P.Message.RequestReplicationSignature
  alias Archethic.TransactionChain.Transaction.ProofOfValidation

  test "serialize/deserialize" do
    proof = %ProofOfValidation{
      signature: :crypto.strong_rand_bytes(96),
      nodes_bitmask: <<0::5, -1::3, 0::2>>
    }

    msg = %RequestReplicationSignature{
      address: random_address(),
      genesis_address: random_address(),
      proof_of_validation: proof
    }

    assert {^msg, <<>>} =
             msg
             |> RequestReplicationSignature.serialize()
             |> RequestReplicationSignature.deserialize()
  end
end
