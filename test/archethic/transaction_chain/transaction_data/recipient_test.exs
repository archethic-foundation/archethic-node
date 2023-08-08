defmodule Archethic.TransactionChain.TransactionData.RecipientTest do
  @moduledoc false
  alias Archethic.TransactionChain.TransactionData.Recipient

  use ArchethicCase
  import ArchethicCase

  describe "serialize/deserialize" do
    test "should work on binary recipient" do
      recipient = random_address()

      assert {^recipient, <<>>} = recipient |> Recipient.serialize(1) |> Recipient.deserialize(1)
    end

    test "should work on struct recipient" do
      recipient = %Recipient{
        address: random_address(),
        action: "vote_for",
        args: ["Ms. Jackson"]
      }

      assert {^recipient, <<>>} = recipient |> Recipient.serialize(1) |> Recipient.deserialize(1)

      recipient = %Recipient{
        address: random_address(),
        action: "vote_for",
        args: [1, 2, [3, 4], %{"foo" => "bar"}, "hello", random_address()]
      }

      assert {^recipient, <<>>} = recipient |> Recipient.serialize(1) |> Recipient.deserialize(1)
    end
  end
end
