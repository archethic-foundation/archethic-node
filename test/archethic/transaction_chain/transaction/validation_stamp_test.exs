defmodule Archethic.TransactionChain.Transaction.ValidationStampTest do
  use ArchethicCase
  use ExUnitProperties

  import Mox

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  doctest ValidationStamp

  property "symmetric sign/valid validation stamp" do
    check all(
            keypair_seed <- StreamData.binary(length: 32),
            proof_of_work <- StreamData.binary(length: 33),
            proof_of_integrity <- StreamData.binary(length: 33),
            proof_of_election <- StreamData.binary(length: 32),
            ledger_operations <- gen_ledger_operations()
          ) do
      {pub, pv} = Crypto.generate_deterministic_keypair(keypair_seed, :secp256r1)
      expect(MockCrypto, :sign_with_last_key, &Crypto.sign(&1, pv))

      assert %ValidationStamp{
               timestamp: DateTime.utc_now(),
               proof_of_work: proof_of_work,
               proof_of_integrity: proof_of_integrity,
               proof_of_election: proof_of_election,
               ledger_operations: ledger_operations
             }
             |> ValidationStamp.sign()
             |> ValidationStamp.valid_signature?(pub)
    end
  end

  defp gen_ledger_operations do
    gen all(
          fee <- StreamData.positive_integer(),
          transaction_movements <- StreamData.list_of(gen_transaction_movement()),
          unspent_outputs <- StreamData.list_of(gen_unspent_outputs())
        ) do
      %LedgerOperations{
        fee: fee,
        transaction_movements: transaction_movements,
        unspent_outputs: unspent_outputs
      }
    end
  end

  defp gen_transaction_movement do
    gen all(
          to <- StreamData.binary(length: 33),
          amount <- StreamData.positive_integer(),
          type <-
            StreamData.one_of([
              StreamData.constant(:UCO),
              StreamData.tuple({StreamData.constant(:NFT), StreamData.binary(length: 33)})
            ])
        ) do
      %TransactionMovement{to: to, amount: amount, type: type}
    end
  end

  defp gen_unspent_outputs do
    gen all(
          from <- StreamData.binary(length: 33),
          amount <- StreamData.positive_integer(),
          type <-
            StreamData.one_of([
              StreamData.constant(:UCO),
              StreamData.tuple({StreamData.constant(:NFT), StreamData.binary(length: 33)})
            ])
        ) do
      %UnspentOutput{from: from, amount: amount, type: type}
    end
  end
end
