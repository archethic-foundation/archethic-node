defmodule Archethic.P2p.Message.GetCurrentReplicationsAttestationsTest do
  @moduledoc false
  use ExUnit.Case
  import ArchethicCase

  alias Archethic.P2P.Message.GetCurrentReplicationsAttestations

  test "serialization/deserialization" do
    msg = %GetCurrentReplicationsAttestations{
      subsets: Enum.map(0..255, &:binary.encode_unsigned(&1)),
      paging_address: random_address()
    }

    assert {^msg, <<>>} =
             msg
             |> GetCurrentReplicationsAttestations.serialize()
             |> GetCurrentReplicationsAttestations.deserialize()

    msg = %GetCurrentReplicationsAttestations{
      subsets: [],
      paging_address: nil
    }

    assert {^msg, <<>>} =
             msg
             |> GetCurrentReplicationsAttestations.serialize()
             |> GetCurrentReplicationsAttestations.deserialize()
  end
end
