defmodule Archethic.Account.MemTables.StateLedgerTest do
  alias Archethic.Account.MemTables.StateLedger
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  use ArchethicCase
  import ArchethicCase

  describe("get_state_unspent_output/1") do
    test "should return nil if there is not state" do
      address = random_address()
      assert nil == StateLedger.get_unspent_output(address)
    end

    test "should return the utxo when there is a state" do
      address = random_address()
      utxo = random_state_utxo()

      StateLedger.add_unspent_output(address, utxo)
      assert ^utxo = StateLedger.get_unspent_output(address)
    end
  end

  describe "add_unspent_output/2" do
    test "should accept utxo of type state" do
      address = random_address()

      assert :ok = StateLedger.add_unspent_output(address, random_state_utxo())
    end

    test "should raise if utxo is not a state" do
      address = random_address()

      assert_raise(FunctionClauseError, fn ->
        StateLedger.add_unspent_output(address, %VersionedUnspentOutput{
          protocol_version: current_protocol_version(),
          unspent_output: %UnspentOutput{type: :call}
        })
      end)

      assert_raise(FunctionClauseError, fn ->
        StateLedger.add_unspent_output(address, %VersionedUnspentOutput{
          protocol_version: current_protocol_version(),
          unspent_output: %UnspentOutput{type: :UCO}
        })
      end)

      assert_raise(FunctionClauseError, fn ->
        StateLedger.add_unspent_output(address, %VersionedUnspentOutput{
          protocol_version: current_protocol_version(),
          unspent_output: %UnspentOutput{type: {:token, random_address(), 0}}
        })
      end)
    end

    test "should raise if address is invalid" do
      invalid_address = :crypto.strong_rand_bytes(10)

      assert_raise(MatchError, fn ->
        StateLedger.add_unspent_output(invalid_address, random_state_utxo())
      end)
    end
  end

  defp random_state_utxo() do
    %VersionedUnspentOutput{
      protocol_version: current_protocol_version(),
      unspent_output: %UnspentOutput{
        type: :state,
        encoded_payload: :crypto.strong_rand_bytes(30)
      }
    }
  end
end
