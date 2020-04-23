defmodule UnirisCore.Mining.ProofOfWorkTest do
  use ExUnit.Case

  alias UnirisCore.Mining.ProofOfWork
  alias UnirisCore.Transaction
  alias UnirisCore.Crypto
  alias UnirisCore.SharedSecrets

  test "run/1 should return :ok when an origin public key is found for the origin signature" do
    origin_keypairs =
      Enum.map(0..100, fn i ->
        Crypto.generate_deterministic_keypair("seed_#{Integer.to_string(i)}")
      end)

    Enum.each(origin_keypairs, fn {pub, _} ->
      SharedSecrets.add_origin_public_key(:software, pub)
    end)

    {origin_pub, origin_pv} = Enum.random(origin_keypairs)

    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer,
      origin_signature: ""
    }

    sig =
      Crypto.sign(
        Map.take(tx, [
          :address,
          :type,
          :timestamp,
          :data,
          :previous_public_key,
          :previous_signature
        ]),
        origin_pv
      )

    tx = %{tx | origin_signature: sig}

    pow = ProofOfWork.run(tx)
    assert pow == origin_pub
  end

  test "run/1 should return an empty string when not origin public key matches the origin signature" do
    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer,
      origin_signature: ""
    }

    assert "" == ProofOfWork.run(tx)
  end

  test "verify?/2 should return true when the proof of matches the origin signature" do
    origin_keypairs =
      Enum.map(0..100, fn i ->
        Crypto.generate_deterministic_keypair("seed_#{Integer.to_string(i)}")
      end)

    Enum.each(origin_keypairs, fn {pub, _} ->
      SharedSecrets.add_origin_public_key(:software, pub)
    end)

    {_, origin_pv} = Enum.random(origin_keypairs)

    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer,
      origin_signature: ""
    }

    sig =
      Crypto.sign(
        Map.take(tx, [
          :address,
          :type,
          :timestamp,
          :data,
          :previous_public_key,
          :previous_signature
        ]),
        origin_pv
      )

    tx = %{tx | origin_signature: sig}

    pow = ProofOfWork.run(tx)

    assert true == ProofOfWork.verify?(tx, pow)
  end

  test "verify?/2 should return true when the proof of is empty and the pow is not found" do
    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer,
      origin_signature: ""
    }

    assert true == ProofOfWork.verify?(tx, "")
  end

  test "verify?/2 should return false when the proof of is empty and but the proof of work exists" do
    origin_keypairs =
      Enum.map(0..100, fn i ->
        Crypto.generate_deterministic_keypair("seed_#{Integer.to_string(i)}")
      end)

    _ =
      Enum.map(origin_keypairs, fn {pub, _} ->
        SharedSecrets.add_origin_public_key(:software, pub)
        pub
      end)

    {_, origin_pv} = Enum.random(origin_keypairs)

    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer,
      origin_signature: ""
    }

    sig =
      Crypto.sign(
        Map.take(tx, [
          :address,
          :type,
          :timestamp,
          :data,
          :previous_public_key,
          :previous_signature
        ]),
        origin_pv
      )

    tx = %{tx | origin_signature: sig}

    assert false == ProofOfWork.verify?(tx, "")
  end
end
