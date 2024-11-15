defmodule Archethic.TransactionChain.Transaction.ProofOfReplicationTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ProofOfReplication
  alias Archethic.TransactionChain.Transaction.ProofOfReplication.ElectedNodes
  alias Archethic.TransactionChain.Transaction.ProofOfReplication.Signature

  alias Archethic.TransactionFactory

  @nb_nodes 53

  setup do
    nodes =
      Enum.map(1..@nb_nodes, fn i ->
        seed = :crypto.strong_rand_bytes(32)
        {mining_pub, mining_pv} = seed |> Crypto.generate_deterministic_keypair(:bls)

        # patch needed to satisfy election geo distribution
        patch = "#{i |> rem(16) |> Integer.to_string(16)}AA"

        node =
          new_node(
            first_public_key: seed |> Crypto.derive_keypair(0) |> elem(0),
            last_public_key: seed |> Crypto.derive_keypair(1) |> elem(0),
            mining_public_key: mining_pub,
            geo_patch: patch,
            network_path: patch
          )

        P2P.add_and_connect_node(node)
        {mining_pv, node}
      end)

    tx = %Transaction{address: tx_address} = TransactionFactory.create_valid_transaction()
    genesis = Transaction.previous_address(tx)
    tx_summary = TransactionSummary.from_transaction(tx, genesis)

    %ElectedNodes{storage_nodes: storage_nodes, required_signatures: required_signatures} =
      P2P.authorized_and_available_nodes() |> ProofOfReplication.get_election(tx_address)

    mapped_storage_nodes =
      Enum.map(storage_nodes, fn node -> Enum.find(nodes, &(elem(&1, 1) == node)) end)

    proof_signatures = Enum.map(mapped_storage_nodes, &create_proof_signature(&1, tx_summary))

    # Ensure election have less nodes than the total number of nodes
    assert tx_address |> Election.storage_nodes(P2P.authorized_and_available_nodes()) |> length() !=
             length(nodes)

    %{
      nodes: nodes,
      transaction_summary: tx_summary,
      proof_signatures: proof_signatures,
      required_signatures: required_signatures
    }
  end

  describe "get_state/2" do
    test "should return :reached when threshold is reached", %{
      transaction_summary: %TransactionSummary{address: tx_address},
      proof_signatures: proof_signatures,
      required_signatures: required_signatures
    } do
      assert :reached ==
               P2P.authorized_and_available_nodes()
               |> ProofOfReplication.get_election(tx_address)
               |> ProofOfReplication.get_state(proof_signatures)

      threshold_proof = Enum.take_random(proof_signatures, required_signatures)

      assert :reached ==
               P2P.authorized_and_available_nodes()
               |> ProofOfReplication.get_election(tx_address)
               |> ProofOfReplication.get_state(threshold_proof)
    end

    test "should return :not_reached when required number is not reached but still possible", %{
      transaction_summary: %TransactionSummary{address: tx_address},
      proof_signatures: proof_signatures,
      required_signatures: required_signatures
    } do
      some_proof_signatures = Enum.take_random(proof_signatures, required_signatures - 1)

      assert :not_reached ==
               P2P.authorized_and_available_nodes()
               |> ProofOfReplication.get_election(tx_address)
               |> ProofOfReplication.get_state(some_proof_signatures)
    end
  end

  describe "elected_node?/2" do
    test "should return true if node is elected", %{
      transaction_summary: %TransactionSummary{address: tx_address},
      proof_signatures: [signature | _]
    } do
      assert P2P.authorized_and_available_nodes()
             |> ProofOfReplication.get_election(tx_address)
             |> ProofOfReplication.elected_node?(signature)
    end

    test "should return false if node is not elected", %{
      transaction_summary: tx_summary = %TransactionSummary{address: tx_address},
      nodes: nodes
    } do
      elected_nodes =
        %ElectedNodes{storage_nodes: storage_nodes} =
        P2P.authorized_and_available_nodes() |> ProofOfReplication.get_election(tx_address)

      not_elected_node =
        Enum.find(nodes, fn {_, node} -> not Enum.member?(storage_nodes, node) end)

      invalid_signature = create_proof_signature(not_elected_node, tx_summary)

      refute ProofOfReplication.elected_node?(elected_nodes, invalid_signature)
    end
  end

  describe "create/2" do
    test "should aggregate signatures and create bitmask of which node signed", %{
      transaction_summary: %TransactionSummary{address: tx_address},
      proof_signatures: proof_signatures
    } do
      nb_signatures = length(proof_signatures)
      expected_bitmask = <<-1::integer-size(nb_signatures)>>

      assert %ProofOfReplication{signature: <<_::768>>, nodes_bitmask: ^expected_bitmask} =
               P2P.authorized_and_available_nodes()
               |> ProofOfReplication.get_election(tx_address)
               |> ProofOfReplication.create(proof_signatures)

      [_, _ | proof_signatures] = proof_signatures

      # removed two first nodes
      expected_bitmask = <<0::2, -1::integer-size(nb_signatures - 2)>>

      assert %ProofOfReplication{signature: <<_::768>>, nodes_bitmask: ^expected_bitmask} =
               P2P.authorized_and_available_nodes()
               |> ProofOfReplication.get_election(tx_address)
               |> ProofOfReplication.create(proof_signatures)
    end
  end

  describe "valid?/2" do
    test "should return true if proof reach threshold and signature is valid", %{
      transaction_summary: tx_summary = %TransactionSummary{address: tx_address},
      proof_signatures: proof_signatures
    } do
      proof =
        P2P.authorized_and_available_nodes()
        |> ProofOfReplication.get_election(tx_address)
        |> ProofOfReplication.create(proof_signatures)

      assert P2P.authorized_and_available_nodes()
             |> ProofOfReplication.get_election(tx_address)
             |> ProofOfReplication.valid?(proof, tx_summary)
    end

    test "should return false if proof does not reach threshold and signature is valid", %{
      transaction_summary: tx_summary = %TransactionSummary{address: tx_address},
      proof_signatures: proof_signatures,
      required_signatures: required_signatures
    } do
      proof_signatures = Enum.take(proof_signatures, required_signatures - 1)

      proof =
        P2P.authorized_and_available_nodes()
        |> ProofOfReplication.get_election(tx_address)
        |> ProofOfReplication.create(proof_signatures)

      refute P2P.authorized_and_available_nodes()
             |> ProofOfReplication.get_election(tx_address)
             |> ProofOfReplication.valid?(proof, tx_summary)
    end

    test "should return false if proof reach threshold and signature is invalid", %{
      transaction_summary: tx_summary = %TransactionSummary{address: tx_address},
      proof_signatures: proof_signatures
    } do
      proof =
        P2P.authorized_and_available_nodes()
        |> ProofOfReplication.get_election(tx_address)
        |> ProofOfReplication.create(proof_signatures)
        |> Map.put(:signature, :crypto.strong_rand_bytes(96))

      refute P2P.authorized_and_available_nodes()
             |> ProofOfReplication.get_election(tx_address)
             |> ProofOfReplication.valid?(proof, tx_summary)
    end

    test "should return false if signer nodes are not the elected ones", %{
      nodes: nodes,
      transaction_summary: tx_summary = %TransactionSummary{address: tx_address},
      proof_signatures: proof_signatures,
      required_signatures: required_signatures
    } do
      elected_nodes =
        %ElectedNodes{storage_nodes: storage_nodes} =
        P2P.authorized_and_available_nodes() |> ProofOfReplication.get_election(tx_address)

      not_elected_node =
        Enum.find(nodes, fn {_, node} -> not Enum.member?(storage_nodes, node) end)

      invalid_proof_signature = create_proof_signature(not_elected_node, tx_summary)

      proof_signatures = Enum.take_random(proof_signatures, required_signatures - 1)

      proof =
        ProofOfReplication.create(elected_nodes, [invalid_proof_signature | proof_signatures])

      refute ProofOfReplication.valid?(elected_nodes, proof, tx_summary)
    end
  end

  describe "get_nodes/2" do
    test "should return nodes which signed the proof", %{
      transaction_summary: %TransactionSummary{address: tx_address},
      proof_signatures: proof_signatures
    } do
      elected_nodes =
        %ElectedNodes{storage_nodes: storage_nodes} =
        P2P.authorized_and_available_nodes() |> ProofOfReplication.get_election(tx_address)

      [_, _ | proof_signatures] = proof_signatures
      proof = ProofOfReplication.create(elected_nodes, proof_signatures)

      proof_nodes = ProofOfReplication.get_nodes(elected_nodes, proof)

      [_, _ | storage_nodes] = storage_nodes
      assert proof_nodes == storage_nodes
    end
  end

  describe "serialization" do
    test "should serialize and deserialize properly", %{
      transaction_summary: %TransactionSummary{address: tx_address},
      proof_signatures: proof_signatures
    } do
      proof =
        P2P.authorized_and_available_nodes()
        |> ProofOfReplication.get_election(tx_address)
        |> ProofOfReplication.create(proof_signatures)

      assert {proof, ""} ==
               proof |> ProofOfReplication.serialize() |> ProofOfReplication.deserialize()
    end
  end

  defp create_proof_signature(
         {pv, %Node{mining_public_key: mining_public_key, first_public_key: first_public_key}},
         tx_summary
       ) do
    raw_data = TransactionSummary.serialize(tx_summary)

    %Signature{
      node_public_key: first_public_key,
      node_mining_key: mining_public_key,
      signature: Crypto.sign(raw_data, pv)
    }
  end
end
