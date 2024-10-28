defmodule Archethic.TransactionChain.Transaction.ProofOfValidationTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ProofOfValidation
  alias Archethic.TransactionChain.Transaction.ProofOfValidation.ElectedNodes

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

    tx =
      %Transaction{address: tx_address, validation_stamp: stamp} =
      TransactionFactory.create_valid_transaction()

    %ElectedNodes{validation_nodes: validation_nodes} =
      P2P.authorized_and_available_nodes() |> ProofOfValidation.get_election(tx_address)

    mapped_validation_nodes =
      Enum.map(validation_nodes, fn node -> Enum.find(nodes, &(elem(&1, 1) == node)) end)

    cross_stamps = Enum.map(mapped_validation_nodes, &create_cross_stamp(&1, stamp, []))

    # Ensure election have less nodes than the total number of nodes
    assert tx_address |> Election.storage_nodes(P2P.authorized_and_available_nodes()) |> length() !=
             length(nodes)

    %{nodes: nodes, transaction: tx, cross_stamps: cross_stamps}
  end

  describe "get_state/2" do
    test "should return :reached when threshold is reached", %{
      nodes: nodes,
      transaction: %Transaction{address: tx_address, validation_stamp: stamp},
      cross_stamps: cross_stamps
    } do
      assert :reached ==
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.get_election(tx_address)
               |> ProofOfValidation.get_state(cross_stamps)

      nb_invalid = @nb_nodes - length(cross_stamps)

      assert nb_invalid > 0

      cross_stamps =
        nodes
        |> Enum.take_random(nb_invalid)
        |> Enum.map(&create_cross_stamp(&1, stamp, [:error]))
        |> Enum.concat(cross_stamps)

      # over threashold with invalid stamps
      assert :reached ==
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.get_election(tx_address)
               |> ProofOfValidation.get_state(cross_stamps)
    end

    test "should return :not_reached when required number is not reached but still possible", %{
      transaction: %Transaction{address: tx_address},
      cross_stamps: cross_stamps
    } do
      nb_validation = length(cross_stamps)
      some_stamps = Enum.take_random(cross_stamps, nb_validation - 2)

      assert :not_reached ==
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.get_election(tx_address)
               |> ProofOfValidation.get_state(some_stamps)

      # Should work once overbooking will be done
      # cross_stamps =
      #   nodes
      #   |> Enum.take_random(2)
      #   |> Enum.map(&create_cross_stamp(&1, stamp, [:error]))
      #   |> Enum.concat(some_stamps)
      #
      # assert :not_reached ==
      #          P2P.authorized_and_available_nodes()
      #          |> ProofOfValidation.get_election(tx_address)
      #          |> ProofOfValidation.get_state(cross_stamps)
    end

    test "should return :error when it's impossible to reach threashold", %{
      nodes: nodes,
      transaction: %Transaction{address: tx_address, validation_stamp: stamp},
      cross_stamps: cross_stamps
    } do
      nb_validation = length(cross_stamps)
      some_stamps = Enum.take_random(cross_stamps, nb_validation - 2)

      assert :not_reached ==
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.get_election(tx_address)
               |> ProofOfValidation.get_state(some_stamps)

      nb_invalid = @nb_nodes - nb_validation

      assert nb_invalid > 0

      cross_stamps =
        nodes
        |> Enum.take_random(nb_invalid)
        |> Enum.map(&create_cross_stamp(&1, stamp, [:error]))
        |> Enum.concat(some_stamps)

      assert :error ==
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.get_election(tx_address)
               |> ProofOfValidation.get_state(cross_stamps)
    end
  end

  describe "create/2" do
    test "should aggregate cross stamps signature and create bitmask of which node signed", %{
      transaction: %Transaction{address: tx_address},
      cross_stamps: cross_stamps
    } do
      %ElectedNodes{required_validations: required_validations} =
        P2P.authorized_and_available_nodes() |> ProofOfValidation.get_election(tx_address)

      expected_bitmask = <<-1::integer-size(required_validations)>>

      assert %ProofOfValidation{signature: <<_::768>>, nodes_bitmask: ^expected_bitmask} =
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.get_election(tx_address)
               |> ProofOfValidation.create(cross_stamps)

      [_, _ | cross_stamps] = cross_stamps

      # removed two first nodes
      expected_bitmask = <<0::2, -1::integer-size(required_validations - 2)>>

      assert %ProofOfValidation{signature: <<_::768>>, nodes_bitmask: ^expected_bitmask} =
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.get_election(tx_address)
               |> ProofOfValidation.create(cross_stamps)
    end
  end

  describe "valid?/2" do
    test "should return true if proof reach threashold and signature is valid", %{
      transaction: %Transaction{address: tx_address, validation_stamp: stamp},
      cross_stamps: cross_stamps
    } do
      proof =
        P2P.authorized_and_available_nodes()
        |> ProofOfValidation.get_election(tx_address)
        |> ProofOfValidation.create(cross_stamps)

      assert P2P.authorized_and_available_nodes()
             |> ProofOfValidation.get_election(tx_address)
             |> ProofOfValidation.valid?(proof, stamp)
    end

    test "should return false if proof does not reach threashold and signature is valid", %{
      transaction: %Transaction{address: tx_address, validation_stamp: stamp},
      cross_stamps: cross_stamps
    } do
      nb_validation = length(cross_stamps)
      cross_stamps = Enum.take(cross_stamps, nb_validation - 2)

      proof =
        P2P.authorized_and_available_nodes()
        |> ProofOfValidation.get_election(tx_address)
        |> ProofOfValidation.create(cross_stamps)

      refute P2P.authorized_and_available_nodes()
             |> ProofOfValidation.get_election(tx_address)
             |> ProofOfValidation.valid?(proof, stamp)
    end

    test "should return false if proof reach threashold and signature is invalid", %{
      transaction: %Transaction{address: tx_address, validation_stamp: stamp},
      cross_stamps: cross_stamps
    } do
      proof =
        P2P.authorized_and_available_nodes()
        |> ProofOfValidation.get_election(tx_address)
        |> ProofOfValidation.create(cross_stamps)
        |> Map.put(:signature, :crypto.strong_rand_bytes(96))

      refute P2P.authorized_and_available_nodes()
             |> ProofOfValidation.get_election(tx_address)
             |> ProofOfValidation.valid?(proof, stamp)
    end

    test "should return false if signer nodes are not the elected ones", %{
      nodes: nodes,
      transaction: %Transaction{address: tx_address, validation_stamp: stamp},
      cross_stamps: cross_stamps
    } do
      elected_nodes =
        %ElectedNodes{validation_nodes: validation_nodes} =
        P2P.authorized_and_available_nodes() |> ProofOfValidation.get_election(tx_address)

      not_elected_node =
        Enum.find(nodes, fn {_, node} -> not Enum.member?(validation_nodes, node) end)

      invalid_cross_stamp = create_cross_stamp(not_elected_node, stamp, [])

      [_ | cross_stamps] = cross_stamps

      proof = ProofOfValidation.create(elected_nodes, [invalid_cross_stamp | cross_stamps])

      refute ProofOfValidation.valid?(elected_nodes, proof, stamp)
    end
  end

  describe "get_nodes/2" do
    test "should return nodes which signed the proof", %{
      transaction: %Transaction{address: tx_address},
      cross_stamps: cross_stamps
    } do
      elected_nodes =
        %ElectedNodes{validation_nodes: validation_nodes} =
        P2P.authorized_and_available_nodes() |> ProofOfValidation.get_election(tx_address)

      [_, _ | cross_stamps] = cross_stamps
      proof = ProofOfValidation.create(elected_nodes, cross_stamps)

      proof_nodes = ProofOfValidation.get_nodes(elected_nodes, proof)

      [_, _ | validation_nodes] = validation_nodes
      assert proof_nodes == validation_nodes
    end
  end

  describe "serialization" do
    test "should serialize and deserialize properly", %{
      transaction: %Transaction{address: tx_address},
      cross_stamps: cross_stamps
    } do
      proof =
        P2P.authorized_and_available_nodes()
        |> ProofOfValidation.get_election(tx_address)
        |> ProofOfValidation.create(cross_stamps)

      assert {proof, ""} ==
               proof |> ProofOfValidation.serialize() |> ProofOfValidation.deserialize()
    end
  end

  defp create_cross_stamp(
         {pv, %Node{mining_public_key: mining_public_key, first_public_key: first_public_key}},
         stamp,
         inconsistencies
       ) do
    raw_data = CrossValidationStamp.get_raw_data_to_sign(stamp, inconsistencies)

    cross_stamp = %CrossValidationStamp{
      node_public_key: mining_public_key,
      signature: Crypto.sign(raw_data, pv),
      inconsistencies: inconsistencies
    }

    {first_public_key, cross_stamp}
  end
end
