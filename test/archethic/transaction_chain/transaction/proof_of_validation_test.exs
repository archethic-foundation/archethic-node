defmodule Archethic.TransactionChain.Transaction.ProofOfValidationTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.Election.StorageConstraints
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ProofOfValidation

  alias Archethic.TransactionFactory

  @nb_nodes 53

  setup do
    nodes =
      Enum.map(1..@nb_nodes, fn _ ->
        seed = :crypto.strong_rand_bytes(32)
        {mining_pub, mining_pv} = seed |> Crypto.generate_deterministic_keypair(:bls)

        node =
          new_node(
            first_public_key: seed |> Crypto.derive_keypair(0) |> elem(0),
            last_public_key: seed |> Crypto.derive_keypair(1) |> elem(0),
            mining_public_key: mining_pub
          )

        P2P.add_and_connect_node(node)
        {mining_pv, node}
      end)

    %StorageConstraints{number_replicas: nb_replicas_fn} = Election.get_storage_constraints()

    nb_validation_nodes =
      DateTime.utc_now() |> P2P.authorized_and_available_nodes() |> nb_replicas_fn.()

    %{nodes: nodes, nb_validation_nodes: nb_validation_nodes}
  end

  describe "get_state/2" do
    test "should return :reached when threshold is reached", %{
      nodes: nodes,
      nb_validation_nodes: nb_validation_nodes
    } do
      %Transaction{validation_stamp: stamp} = TransactionFactory.create_valid_transaction()

      cross_stamps =
        nodes |> Enum.take(nb_validation_nodes) |> Enum.map(&create_cross_stamp(&1, stamp, []))

      # Threashold egal
      assert :reached ==
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.sort_nodes()
               |> ProofOfValidation.get_state(cross_stamps)

      nb_invalid = @nb_nodes - length(cross_stamps)

      assert nb_invalid > 0

      cross_stamps =
        nodes
        |> Enum.take(-nb_invalid)
        |> Enum.map(&create_cross_stamp(&1, stamp, [:error]))
        |> Enum.concat(cross_stamps)

      # over threashold with invalid stamps
      assert :reached ==
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.sort_nodes()
               |> ProofOfValidation.get_state(cross_stamps)

      cross_stamps =
        nodes
        |> Enum.take(nb_validation_nodes + 1)
        |> Enum.map(&create_cross_stamp(&1, stamp, []))

      # over threashold
      assert :reached ==
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.sort_nodes()
               |> ProofOfValidation.get_state(cross_stamps)
    end

    test "should return :not_reached when required number is not reached but still possible", %{
      nodes: nodes,
      nb_validation_nodes: nb_validation_nodes
    } do
      %Transaction{validation_stamp: stamp} = TransactionFactory.create_valid_transaction()

      cross_stamps =
        nodes
        |> Enum.take(nb_validation_nodes - 2)
        |> Enum.map(&create_cross_stamp(&1, stamp, []))

      assert :not_reached ==
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.sort_nodes()
               |> ProofOfValidation.get_state(cross_stamps)

      nb_invalid = @nb_nodes - (length(cross_stamps) + 2)

      assert nb_invalid > 0

      cross_stamps =
        nodes
        |> Enum.take(-nb_invalid)
        |> Enum.map(&create_cross_stamp(&1, stamp, [:error]))
        |> Enum.concat(cross_stamps)

      assert :not_reached ==
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.sort_nodes()
               |> ProofOfValidation.get_state(cross_stamps)
    end

    test "should return :error when it's impossible to reach threashold", %{
      nodes: nodes,
      nb_validation_nodes: nb_validation_nodes
    } do
      %Transaction{validation_stamp: stamp} = TransactionFactory.create_valid_transaction()

      cross_stamps =
        nodes
        |> Enum.take(nb_validation_nodes - 2)
        |> Enum.map(&create_cross_stamp(&1, stamp, []))

      assert :not_reached ==
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.sort_nodes()
               |> ProofOfValidation.get_state(cross_stamps)

      nb_invalid = @nb_nodes - length(cross_stamps)

      assert nb_invalid > 0

      cross_stamps =
        nodes
        |> Enum.take(-nb_invalid)
        |> Enum.map(&create_cross_stamp(&1, stamp, [:error]))
        |> Enum.concat(cross_stamps)

      assert :error ==
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.sort_nodes()
               |> ProofOfValidation.get_state(cross_stamps)
    end
  end

  describe "create/2" do
    test "should aggregate cross stamps signature and create bitmask of which node signed", %{
      nodes: nodes,
      nb_validation_nodes: nb_validation_nodes
    } do
      %Transaction{validation_stamp: stamp} = TransactionFactory.create_valid_transaction()

      nodes = Enum.sort_by(nodes, &elem(&1, 1).first_public_key)

      cross_stamps =
        nodes |> Enum.take(nb_validation_nodes) |> Enum.map(&create_cross_stamp(&1, stamp, []))

      expected_bitmask = <<-1::integer-size(nb_validation_nodes)>>

      assert %ProofOfValidation{signature: <<_::768>>, nodes_bitmask: ^expected_bitmask} =
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.sort_nodes()
               |> ProofOfValidation.create(cross_stamps)

      inter_nodes = length(nodes) - nb_validation_nodes - 2

      assert inter_nodes > 0

      cross_stamps =
        nodes
        |> Enum.take(-2)
        |> Enum.map(&create_cross_stamp(&1, stamp, []))
        |> Enum.concat(cross_stamps)

      # first nodes in the list + 2 last signed
      expected_bitmask =
        <<-1::integer-size(nb_validation_nodes), 0::integer-size(inter_nodes), -1::2>>

      assert %ProofOfValidation{signature: <<_::768>>, nodes_bitmask: ^expected_bitmask} =
               P2P.authorized_and_available_nodes()
               |> ProofOfValidation.sort_nodes()
               |> ProofOfValidation.create(cross_stamps)
    end
  end

  describe "valid?/2" do
    test "should return true if proof reach threashold and signature is valid", %{
      nodes: nodes,
      nb_validation_nodes: nb_validation_nodes
    } do
      %Transaction{validation_stamp: stamp} = TransactionFactory.create_valid_transaction()

      cross_stamps =
        nodes |> Enum.take(nb_validation_nodes) |> Enum.map(&create_cross_stamp(&1, stamp, []))

      proof =
        P2P.authorized_and_available_nodes()
        |> ProofOfValidation.sort_nodes()
        |> ProofOfValidation.create(cross_stamps)

      assert P2P.authorized_and_available_nodes()
             |> ProofOfValidation.sort_nodes()
             |> ProofOfValidation.valid?(proof, stamp)
    end

    test "should return false if proof does not reach threashold and signature is valid", %{
      nodes: nodes,
      nb_validation_nodes: nb_validation_nodes
    } do
      %Transaction{validation_stamp: stamp} = TransactionFactory.create_valid_transaction()

      cross_stamps =
        nodes
        |> Enum.take(nb_validation_nodes - 1)
        |> Enum.map(&create_cross_stamp(&1, stamp, []))

      proof =
        P2P.authorized_and_available_nodes()
        |> ProofOfValidation.sort_nodes()
        |> ProofOfValidation.create(cross_stamps)

      refute P2P.authorized_and_available_nodes()
             |> ProofOfValidation.sort_nodes()
             |> ProofOfValidation.valid?(proof, stamp)
    end

    test "should return false if proof reach threashold and signature is invalid", %{
      nodes: nodes,
      nb_validation_nodes: nb_validation_nodes
    } do
      %Transaction{validation_stamp: stamp} = TransactionFactory.create_valid_transaction()

      cross_stamps =
        nodes |> Enum.take(nb_validation_nodes) |> Enum.map(&create_cross_stamp(&1, stamp, []))

      proof =
        P2P.authorized_and_available_nodes()
        |> ProofOfValidation.sort_nodes()
        |> ProofOfValidation.create(cross_stamps)
        |> Map.put(:signature, :crypto.strong_rand_bytes(96))

      refute P2P.authorized_and_available_nodes()
             |> ProofOfValidation.sort_nodes()
             |> ProofOfValidation.valid?(proof, stamp)
    end
  end

  describe "get_nodes/2" do
    test "should return nodes which signed the proof", %{
      nodes: nodes,
      nb_validation_nodes: nb_validation_nodes
    } do
      %Transaction{validation_stamp: stamp} = TransactionFactory.create_valid_transaction()

      signer_nodes = Enum.take_random(nodes, nb_validation_nodes)
      cross_stamps = Enum.map(signer_nodes, &create_cross_stamp(&1, stamp, []))

      proof =
        P2P.authorized_and_available_nodes()
        |> ProofOfValidation.sort_nodes()
        |> ProofOfValidation.create(cross_stamps)

      signer_nodes = Enum.map(signer_nodes, &elem(&1, 1))

      proof_nodes =
        P2P.authorized_and_available_nodes()
        |> ProofOfValidation.sort_nodes()
        |> ProofOfValidation.get_nodes(proof)

      assert Enum.all?(proof_nodes, &Enum.member?(signer_nodes, &1)) and
               length(proof_nodes) == length(signer_nodes)
    end
  end

  describe "serialization" do
    test "should serialize and deserialize properly", %{
      nodes: nodes,
      nb_validation_nodes: nb_validation_nodes
    } do
      %Transaction{validation_stamp: stamp} = TransactionFactory.create_valid_transaction()

      signer_nodes = Enum.take_random(nodes, nb_validation_nodes)
      cross_stamps = Enum.map(signer_nodes, &create_cross_stamp(&1, stamp, []))

      proof =
        P2P.authorized_and_available_nodes()
        |> ProofOfValidation.sort_nodes()
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
