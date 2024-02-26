defmodule Archethic.TransactionChain.DBLedger.FileImplTest do
  use ArchethicCase

  alias Archethic.TransactionChain.DBLedger.FileImpl, as: DBLedger

  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.TransactionInput

  setup do
    DBLedger.setup_folder!()
    :ok
  end

  describe "Write/Get the inputs" do
    test "returns empty when there is none" do
      assert ArchethicCase.random_address() |> DBLedger.stream_inputs() |> Enum.empty?()
    end

    test "returns the inputs that were appended" do
      address = ArchethicCase.random_address()
      address2 = ArchethicCase.random_address()
      address3 = ArchethicCase.random_address()

      inputs = [
        %VersionedTransactionInput{
          protocol_version: ArchethicCase.current_protocol_version(),
          input: %TransactionInput{
            amount: 100_000_000,
            type: :UCO,
            from: address2,
            timestamp: ~U[2022-11-14 14:54:12.000Z]
          }
        },
        %VersionedTransactionInput{
          protocol_version: ArchethicCase.current_protocol_version(),
          input: %TransactionInput{
            amount: 200_000_000,
            type: :UCO,
            from: address3,
            timestamp: ~U[2022-11-14 14:54:12.000Z]
          }
        }
      ]

      DBLedger.write_inputs(address, inputs)

      assert [
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   amount: 100_000_000,
                   type: :UCO,
                   from: address2,
                   timestamp: ~U[2022-11-14 14:54:12.000Z]
                 }
               },
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   amount: 200_000_000,
                   type: :UCO,
                   from: address3,
                   timestamp: ~U[2022-11-14 14:54:12.000Z]
                 }
               }
             ] =
               address
               |> DBLedger.stream_inputs()
               |> Enum.to_list()

      assert address2 |> DBLedger.stream_inputs() |> Enum.empty?()
      assert address3 |> DBLedger.stream_inputs() |> Enum.empty?()
    end
  end
end
