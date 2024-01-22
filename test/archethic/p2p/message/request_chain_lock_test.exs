defmodule Archethic.P2P.Message.RequestChainLockTest do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.Mining.ChainLock
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Error
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.RequestChainLock

  use ArchethicCase
  import ArchethicCase

  describe "serialization" do
    test "should serialize and deserialize message" do
      address = random_address()
      hash = Crypto.hash(address)

      message = %RequestChainLock{address: address, hash: hash}

      assert message == message |> Message.encode() |> Message.decode() |> elem(0)
    end
  end

  describe "process" do
    test "should lock an address and return Ok" do
      address = random_address()
      hash1 = Crypto.hash(address)
      hash2 = Crypto.hash(hash1)

      message = %RequestChainLock{address: address, hash: hash1}

      assert %Ok{} == Message.process(message, random_public_key())
      assert {:error, :already_locked} == ChainLock.lock(address, hash2)
    end

    test "should return Error if address is already locked" do
      address = random_address()
      hash1 = Crypto.hash(address)
      hash2 = Crypto.hash(hash1)

      assert :ok == ChainLock.lock(address, hash1)

      message = %RequestChainLock{address: address, hash: hash2}

      assert %Error{reason: :already_locked} == Message.process(message, random_public_key())
    end
  end
end
