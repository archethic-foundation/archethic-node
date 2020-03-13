defmodule UnirisValidation.DefaultImpl.ProofOfWorkTest do
  use ExUnit.Case, async: false

  alias UnirisChain.Transaction
  alias UnirisCrypto, as: Crypto
  alias UnirisValidation.DefaultImpl.ProofOfWork, as: POW

  import Mox

  setup :verify_on_exit!

  setup_all do
    Crypto.add_origin_seed("first_seed")
    {:ok, %{origin_public_keys: Crypto.origin_public_keys()}}
  end

  test "run/1 should return :ok when an origin public key is found for the origin signature", %{
    origin_public_keys: origin_public_keys
  } do
    stub(MockSharedSecrets, :origin_public_keys, fn _ -> origin_public_keys end)
    tx = Transaction.from_seed("seed", :transfer)
    assert {:ok, pow} = POW.run(tx)
  end

  test "run/1 should return {:error, :not_found} when not origin public key matches the origin signature" do
    stub(MockSharedSecrets, :origin_public_keys, fn _ -> [] end)

    tx = Transaction.from_seed("seed", :transfer)

    assert {:error, :not_found} = POW.run(tx)
  end

  test "verify/2 should return :ok when the proof of matches the origin signature", %{
    origin_public_keys: origin_public_keys
  } do
    stub(MockSharedSecrets, :origin_public_keys, fn _ -> origin_public_keys end)
    tx = Transaction.from_seed("seed", :transfer)
    assert true = POW.verify(tx, List.first(origin_public_keys))
  end

  test "verify/2 should return :ok when the proof of work is not found and recheck does notmatch it" do
    stub(MockSharedSecrets, :origin_public_keys, fn _ -> [] end)
    tx = Transaction.from_seed("seed", :transfer)
    assert true = POW.verify(tx, "")
  end
end
