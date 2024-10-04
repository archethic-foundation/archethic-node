defmodule Archethic.P2P.Message.ProofOfValidationDoneTest do
  @moduledoc false
  use ArchethicCase
  import ArchethicCase

  alias Archethic.P2P.Message.ProofOfValidationDone
  alias Archethic.TransactionChain.Transaction.ProofOfValidation

  test "serialize/deserialize" do
    proof = %ProofOfValidation{
      signature: :crypto.strong_rand_bytes(96),
      nodes_bitmask: <<0::5, -1::3, 0::2>>
    }

    msg = %ProofOfValidationDone{address: random_address(), proof_of_validation: proof}

    assert {^msg, <<>>} =
             msg
             |> ProofOfValidationDone.serialize()
             |> ProofOfValidationDone.deserialize()
  end
end
