defmodule Archethic.P2P.Message.ReplicationErrorTest do
  @moduledoc false
  use ExUnit.Case

  alias Archethic.Mining.Error
  alias Archethic.P2P.Message.ReplicationError
  alias Archethic.P2P.Message

  doctest Archethic.P2P.Message.ReplicationError

  test "Message.encode()/1  Message.decode()/1  " do
    address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    msg = %ReplicationError{
      address: address,
      error: Error.new(:consensus_not_reached, "Invalid chain")
    }

    assert msg == msg |> Message.encode() |> Message.decode() |> elem(0)
  end
end
