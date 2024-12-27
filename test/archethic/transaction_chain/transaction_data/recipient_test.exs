defmodule Archethic.TransactionChain.TransactionData.RecipientTest do
  @moduledoc false
  use ArchethicCase
  use ExUnitProperties
  import ArchethicCase

  alias Archethic.TransactionChain.TransactionData.Recipient

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

  describe "serialize/deserialize v3" do
    property "symmetric encoding/decoding of recipients arguments as list" do
      check all(
              args <-
                StreamData.list_of(
                  StreamData.one_of([
                    StreamData.integer(),
                    StreamData.string(:alphanumeric),
                    StreamData.boolean(),
                    StreamData.constant(nil)
                  ])
                )
            ) do
        recipient = %Recipient{address: random_address(), action: "action mane", args: args}

        assert {^recipient, <<>>} =
                 recipient
                 |> Recipient.serialize(3, :compact)
                 |> Recipient.deserialize(3, :compact)

        assert {^recipient, <<>>} =
                 recipient
                 |> Recipient.serialize(3, :extended)
                 |> Recipient.deserialize(3, :extended)
      end
    end
  end

  describe "serialize/deserialize v4" do
    property "symmetric encoding/decoding of recipients arguments as map" do
      check all(
              args <-
                StreamData.map_of(
                  StreamData.string(:alphanumeric),
                  StreamData.one_of([
                    StreamData.integer(),
                    StreamData.string(:alphanumeric),
                    StreamData.boolean(),
                    StreamData.constant(nil)
                  ])
                )
            ) do
        version = current_transaction_version()
        recipient = %Recipient{address: random_address(), action: "action mane", args: args}

        assert {^recipient, <<>>} =
                 recipient
                 |> Recipient.serialize(version, :compact)
                 |> Recipient.deserialize(version, :compact)

        assert {^recipient, <<>>} =
                 recipient
                 |> Recipient.serialize(version, :extended)
                 |> Recipient.deserialize(version, :extended)
      end
    end
  end
end
