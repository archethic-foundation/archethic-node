defmodule UnirisValidation.ProofOfWorkTest do
  use ExUnit.Case

  alias UnirisChain.Transaction
  alias UnirisCrypto, as: Crypto
  alias UnirisValidation.ProofOfWork, as: POW

  import Mox

  setup :verify_on_exit!

  test "run/1 should return :ok when an origin public key is found for the origin signature" do
    origin_keyspairs = [
      {<<0, 195, 84, 216, 212, 203, 243, 221, 69, 12, 73, 56, 72, 36, 182, 126, 169, 181, 57, 19,
         136, 12, 49, 220, 138, 27, 238, 216, 110, 230, 9, 61, 135>>,
       <<0, 185, 223, 241, 198, 63, 175, 22, 169, 80, 250, 126, 230, 19, 143, 48, 78, 154, 81, 15,
         70, 197, 195, 14, 144, 116, 203, 211, 27, 237, 151, 18, 174, 195, 84, 216, 212, 203, 243,
         221, 69, 12, 73, 56, 72, 36, 182, 126, 169, 181, 57, 19, 136, 12, 49, 220, 138, 27, 238,
         216, 110, 230, 9, 61, 135>>}
    ]

     [{origin_public_key, _}] = origin_keyspairs

    Crypto.SoftwareImpl.load_origin_keys(origin_keyspairs)

    expect(MockNetwork, :origin_public_keys, fn ->
      Enum.map(0..3, fn _ ->
        Crypto.generate_random_keypair()
      end)
      |> Kernel.++(origin_public_key)
    end)

    tx = %{
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
      type: :transfer
    }

    sig = Crypto.sign(tx, with: :origin, as: :random)
    tx = struct(Transaction, Map.put(tx, :origin_signature, sig))

    assert {:ok, pow} = POW.run(tx)
    assert pow == origin_public_key
  end

  test "run/1 should return {:error, :not_found} when not origin public key matches the origin signature" do
    expect(MockNetwork, :origin_public_keys, fn ->
      Enum.map(0..100, fn _ ->
        Crypto.generate_random_keypair()
      end)
    end)

    tx = %{
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
      type: :transfer
    }

    sig = Crypto.sign(tx, with: :node, as: :last)
    tx = struct(Transaction, Map.put(tx, :origin_signature, sig))

    assert {:error, :not_found} = POW.run(tx)
  end

  test "verify/2 should return :ok when the proof of matches the origin signature" do
    origin_keyspairs = [
      {<<0, 195, 84, 216, 212, 203, 243, 221, 69, 12, 73, 56, 72, 36, 182, 126, 169, 181, 57, 19,
       136, 12, 49, 220, 138, 27, 238, 216, 110, 230, 9, 61, 135>>,
       <<0, 185, 223, 241, 198, 63, 175, 22, 169, 80, 250, 126, 230, 19, 143, 48, 78, 154, 81, 15,
       70, 197, 195, 14, 144, 116, 203, 211, 27, 237, 151, 18, 174, 195, 84, 216, 212, 203, 243,
       221, 69, 12, 73, 56, 72, 36, 182, 126, 169, 181, 57, 19, 136, 12, 49, 220, 138, 27, 238,
       216, 110, 230, 9, 61, 135>>}
    ]

    [{origin_public_key, _}] = origin_keyspairs

    Crypto.SoftwareImpl.load_origin_keys(origin_keyspairs)

    tx = %{
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
      type: :transfer
    }

    sig = Crypto.sign(tx, with: :origin, as: :random)
    tx = struct(Transaction, Map.put(tx, :origin_signature, sig))

    assert true = POW.verify(tx, origin_public_key)
  end

  test "verify/2 should return :ok when the proof of work is not found and recheck does notmatch it" do
    expect(MockNetwork, :origin_public_keys, fn ->
      Enum.map(0..100, fn _ ->
        Crypto.generate_random_keypair()
      end)
    end)

    tx = %{
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
      type: :transfer
    }

    sig = Crypto.sign(tx, with: :node, as: :last)
    tx = struct(Transaction, Map.put(tx, :origin_signature, sig))

    assert true = POW.verify(tx, "")
  end
end
