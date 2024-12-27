defmodule Archethic.Contracts.Contract.ContextTest do
  use ArchethicCase

  import ArchethicCase

  alias Archethic.Contracts.Contract.Context
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.VersionedRecipient

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  doctest Context

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

      recipient =
        %Recipient{address: random_address()}
        |> VersionedRecipient.wrap_recipient(current_transaction_version())

      ctx = %Context{
        status: :tx_output,
        trigger: {:transaction, random_address(), recipient},
        timestamp: now |> DateTime.truncate(:millisecond)
      }

      assert {^ctx, <<>>} = ctx |> Context.serialize() |> Context.deserialize()
    end

    test "trigger=transaction (named action)" do
      now = DateTime.utc_now()

      recipient =
        %Recipient{
          address: random_address(),
          action: "add",
          args: %{"a" => 1, "b" => 2, "c" => 3, "d" => 4, "e" => 5}
        }
        |> VersionedRecipient.wrap_recipient(current_transaction_version())

      ctx = %Context{
        status: :tx_output,
        trigger: {:transaction, random_address(), recipient},
        timestamp: now |> DateTime.truncate(:millisecond)
      }

      assert {^ctx, <<>>} = ctx |> Context.serialize() |> Context.deserialize()
    end
  end
end
