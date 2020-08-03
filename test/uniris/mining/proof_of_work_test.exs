defmodule Uniris.Mining.ProofOfWorkTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.Mining.ProofOfWork

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.Transaction
  alias Uniris.TransactionData

  alias Uniris.SharedSecrets

  import Mox

  describe "find_public_key/1" do
    test "should return the node first public key with first node transaction" do
      tx = Transaction.new(:node, %TransactionData{})
      assert Crypto.node_public_key(0) == ProofOfWork.find_origin_public_key(tx)
    end

    test "should return the node first public key with update node transaction" do
      {first_pub, _} = Crypto.derivate_keypair("seed", 0)

      MockStorage
      |> expect(:get_transaction, fn _ ->
        {:ok, Transaction.new(:node, %TransactionData{}, "seed", 0)}
      end)

      MockCrypto
      |> stub(:node_public_key, fn index ->
        {pub, _} = Crypto.derivate_keypair("seed", index)
        pub
      end)
      |> stub(:sign_with_node_key, fn msg, index ->
        {_, pv} = Crypto.derivate_keypair("seed", index)
        Crypto.sign(msg, pv)
      end)
      |> stub(:number_of_node_keys, fn -> 1 end)

      P2P.add_node(%Node{
        first_public_key: first_pub,
        last_public_key: first_pub,
        ip: {127, 0, 0, 1},
        port: 3000
      })

      tx = Transaction.new(:node, %TransactionData{})
      assert first_pub == ProofOfWork.find_origin_public_key(tx)
    end

    test "should return node first public key with a node shared secrets transactions" do
      {first_pub, _} = Crypto.derivate_keypair("seed", 0)

      P2P.add_node(%Node{
        first_public_key: first_pub,
        last_public_key: first_pub,
        ip: {127, 0, 0, 1},
        port: 3000
      })

      MockCrypto
      |> stub(:node_public_key, fn index ->
        {pub, _} = Crypto.derivate_keypair("seed", index)
        pub
      end)
      |> stub(:sign_with_node_key, fn msg, index ->
        {_, pv} = Crypto.derivate_keypair("seed", index)
        Crypto.sign(msg, pv)
      end)

      tx = Transaction.new(:node_shared_secrets, %TransactionData{})
      assert first_pub == ProofOfWork.find_origin_public_key(tx)
    end

    test "should return origin shared public key" do
      origin_keypairs =
        Enum.map(0..100, fn i ->
          Crypto.generate_deterministic_keypair("seed_#{Integer.to_string(i)}")
        end)

      Enum.each(origin_keypairs, fn {pub, _} ->
        SharedSecrets.add_origin_public_key(:software, pub)
      end)

      Enum.each(origin_keypairs, fn {pub, _} ->
        SharedSecrets.add_origin_public_key(:software, pub)
      end)

      {origin_pub, origin_pv} = Enum.random(origin_keypairs)

      tx = %Transaction{
        address:
          <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
            124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
        data: %TransactionData{},
        previous_public_key:
          <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
            143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
        previous_signature:
          <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
            254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129,
            135, 115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139,
            253, 6, 210, 81, 143, 0, 118, 222, 15>>,
        timestamp: ~U[2020-01-13 16:07:22Z],
        type: :transfer
      }

      sig =
        tx
        |> Transaction.extract_for_origin_signature()
        |> Transaction.serialize()
        |> Crypto.sign(origin_pv)

      tx = %{tx | origin_signature: sig}

      pow = ProofOfWork.find_origin_public_key(tx)
      assert pow == origin_pub
    end

    test "should return empty string when no origin key is matched" do
      tx = %Transaction{
        address:
          <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
            124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
        data: %TransactionData{},
        previous_public_key:
          <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
            143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
        previous_signature:
          <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
            254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129,
            135, 115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139,
            253, 6, 210, 81, 143, 0, 118, 222, 15>>,
        timestamp: ~U[2020-01-13 16:07:22Z],
        type: :transfer,
        origin_signature: ""
      }

      assert "" == ProofOfWork.find_origin_public_key(tx)
    end
  end

  describe "verify/2?" do
    test "should return true when the proof of works matches the origin signature" do
      tx = Transaction.new(:node, %TransactionData{})
      pow = ProofOfWork.find_origin_public_key(tx)

      assert ProofOfWork.verify?(pow, tx)
    end

    test "should return true when the proof of works is empty and the proof of work not found" do
      tx = %Transaction{
        address:
          <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
            124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
        data: %TransactionData{},
        previous_public_key:
          <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
            143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
        previous_signature:
          <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
            254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129,
            135, 115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139,
            253, 6, 210, 81, 143, 0, 118, 222, 15>>,
        timestamp: ~U[2020-01-13 16:07:22Z],
        type: :transfer,
        origin_signature: ""
      }

      assert ProofOfWork.verify?("", tx)
    end

    test "should return falsew when the proof of work is empty but the public key exists" do
      tx = Transaction.new(:node, %TransactionData{})
      assert false == ProofOfWork.verify?("", tx)
    end
  end
end
