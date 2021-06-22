defmodule ArchEthic.Mining.ProofOfWorkTest do
  use ArchEthicCase

  alias ArchEthic.Crypto

  alias ArchEthic.Mining.ProofOfWork

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias ArchEthic.SharedSecrets

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData

  doctest ProofOfWork

  describe "list_origin_public_keys_candidates/1 when it's a transaction with smart contract" do
    test "load the origin public keys based on the origin family provided " do
      :ok =
        P2P.add_and_connect_node(%Node{
          last_public_key: Crypto.first_node_public_key(),
          first_public_key: Crypto.first_node_public_key(),
          ip: {127, 0, 0, 1},
          port: 3000
        })

      other_public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      :ok = SharedSecrets.add_origin_public_key(:biometric, other_public_key)
      :ok = SharedSecrets.add_origin_public_key(:software, :crypto.strong_rand_bytes(32))

      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            code: """
            condition inherit: [
              origin_family: biometric
            ]
            """
          },
          "seed",
          0
        )

      assert [other_public_key] == ProofOfWork.list_origin_public_keys_candidates(tx)
    end
  end
end
