defmodule Archethic.P2P.Message.FirstTransactionAddressTest do
  @moduledoc false
  use ExUnit.Case

  alias Archethic.P2P.Message.FirstTransactionAddress
  alias Archethic.P2P.Message

  doctest FirstTransactionAddress

  test "encode decode" do
    msg2 = %FirstTransactionAddress{
      address: <<0::272>>,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
    }

    assert msg2 ==
             msg2
             |> Message.encode()
             |> Message.decode()
             |> elem(0)
  end
end
