defmodule Archethic.Contracts.Contract.ContextTest do
  use ArchethicCase

  import ArchethicCase

  alias Archethic.Contracts.Contract.Context
  alias Archethic.TransactionChain.TransactionData.Recipient

  describe "serialization" do
    test "trigger=datetime" do
      now = DateTime.utc_now()

      ctx = %Context{
        status: :no_output,
        trigger: {:datetime, now |> DateTime.truncate(:second)},
        timestamp: now |> DateTime.truncate(:millisecond)
      }

      assert {^ctx, <<>>} = ctx |> Context.serialize() |> Context.deserialize()
    end

    test "trigger=interval" do
      now = DateTime.utc_now()

      ctx = %Context{
        status: :tx_output,
        trigger: {:interval, "* */5 * * *", now |> DateTime.truncate(:second)},
        timestamp: now |> DateTime.truncate(:millisecond)
      }

      assert {^ctx, <<>>} = ctx |> Context.serialize() |> Context.deserialize()
    end

    test "trigger=oracle" do
      now = DateTime.utc_now()

      ctx = %Context{
        status: :failure,
        trigger: {:oracle, random_address()},
        timestamp: now |> DateTime.truncate(:millisecond)
      }

      assert {^ctx, <<>>} = ctx |> Context.serialize() |> Context.deserialize()
    end

    test "trigger=transaction" do
      now = DateTime.utc_now()

      ctx = %Context{
        status: :tx_output,
        trigger:
          {:transaction, random_address(),
           %Recipient{
             address: random_address()
           }},
        timestamp: now |> DateTime.truncate(:millisecond)
      }

      assert {^ctx, <<>>} = ctx |> Context.serialize() |> Context.deserialize()
    end

    test "trigger=transaction (named action)" do
      now = DateTime.utc_now()

      ctx = %Context{
        status: :tx_output,
        trigger:
          {:transaction, random_address(),
           %Recipient{
             address: random_address(),
             action: "add",
             args: [1, 2, 3, 4, 5]
           }},
        timestamp: now |> DateTime.truncate(:millisecond)
      }

      assert {^ctx, <<>>} = ctx |> Context.serialize() |> Context.deserialize()
    end
  end
end
