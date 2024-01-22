defmodule Archethic.P2P.Message.UnlockChainTest do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.Mining.ChainLock
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.UnlockChain

  use ArchethicCase
  import ArchethicCase

  describe "serialization" do
    test "should serialize and deserialize message" do
      message = %UnlockChain{address: random_address()}

      assert message == message |> Message.encode() |> Message.decode() |> elem(0)
    end
  end

  describe "process" do
    test "should unlock an address and return Ok" do
      address = random_address()
      hash1 = Crypto.hash(address)
      hash2 = Crypto.hash(hash1)

      ChainLock.lock(address, hash1)

      message = %UnlockChain{address: address}

      assert %Ok{} == Message.process(message, random_public_key())
      assert :ok == ChainLock.lock(address, hash2)
    end
  end
end
