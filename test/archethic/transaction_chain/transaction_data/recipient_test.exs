defmodule Archethic.TransactionChain.TransactionData.RecipientTest do
  @moduledoc false
  alias Archethic.TransactionChain.TransactionData.Recipient

  use ArchethicCase
  import ArchethicCase

  describe "serialize/deserialize v1" do
    test "should work on unnamed action" do
      recipient = %Recipient{
        address: random_address()
      }

      assert {^recipient, <<>>} = recipient |> Recipient.serialize(1) |> Recipient.deserialize(1)
    end
  end

  describe "serialize/deserialize v2" do
    test "should work on unnamed action" do
      recipient = %Recipient{
        address: random_address()
      }

      assert {^recipient, <<>>} = recipient |> Recipient.serialize(2) |> Recipient.deserialize(2)
    end

    test "should work on named action" do
      recipient = %Recipient{
        address: random_address(),
        action: "vote_for",
        args: ["Ms. Jackson"]
      }

      assert {^recipient, <<>>} = recipient |> Recipient.serialize(2) |> Recipient.deserialize(2)

      recipient = %Recipient{
        address: random_address(),
        action: "vote_for",
        args: [1, 2, [3, 4], %{"foo" => "bar"}, "hello", Base.encode16(random_address())]
      }

      assert {^recipient, <<>>} = recipient |> Recipient.serialize(2) |> Recipient.deserialize(2)
    end
  end
end
