defmodule Archethic.P2p.Message.GetCurrentReplicationAttestationsTest do
  @moduledoc false
  use ExUnit.Case

  alias Archethic.P2P.Message.GetCurrentReplicationAttestations

  test "serialization/deserialization" do
    msg = %GetCurrentReplicationAttestations{
      subsets: Enum.map(0..255, &:binary.encode_unsigned(&1))
    }

    assert {^msg, <<>>} =
             msg
             |> GetCurrentReplicationAttestations.serialize()
             |> GetCurrentReplicationAttestations.deserialize()

    msg = %GetCurrentReplicationAttestations{
      subsets: []
    }

    assert {^msg, <<>>} =
             msg
             |> GetCurrentReplicationAttestations.serialize()
             |> GetCurrentReplicationAttestations.deserialize()
  end
end
