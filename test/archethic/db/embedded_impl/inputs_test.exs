defmodule Archethic.DB.EmbeddedImpl.InputsTest do
  use ArchethicCase

  alias Archethic.DB.EmbeddedImpl.InputsReader
  alias Archethic.DB.EmbeddedImpl.InputsWriter

  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.TransactionInput

  describe "Append/Get" do
    test "returns empty when there is none" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      assert [] = InputsReader.get_inputs(:UCO, address)
      assert [] = InputsReader.get_inputs(:token, address)
    end

    test "should not duplicate the inputs if called multiple times" do
      # it means that we can only open the file to write *once*
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      tx = %VersionedTransactionInput{
        protocol_version: 1,
        input: %TransactionInput{
          amount: 1,
          type: :UCO,
          from: address,
          reward?: true,
          spent?: true,
          timestamp: ~U[2022-11-14 14:54:12Z]
        }
      }

      {:ok, pid1} = InputsWriter.start_link(:UCO, address)
      InputsWriter.append_input(pid1, tx)
      InputsWriter.stop(pid1)

      assert [^tx] = InputsReader.get_inputs(:UCO, address)

      {:ok, pid2} = InputsWriter.start_link(:UCO, address)
      InputsWriter.append_input(pid2, tx)
      InputsWriter.stop(pid2)

      assert [^tx] = InputsReader.get_inputs(:UCO, address)
    end

    test "returns the UCO inputs that were appended" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      address2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      address3 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      inputs = [
        %VersionedTransactionInput{
          protocol_version: 1,
          input: %TransactionInput{
            amount: 1,
            type: :UCO,
            from: address2,
            reward?: true,
            spent?: true,
            timestamp: ~U[2022-11-14 14:54:12Z]
          }
        },
        %VersionedTransactionInput{
          protocol_version: 1,
          input: %TransactionInput{
            amount: 2,
            type: :UCO,
            from: address3,
            reward?: true,
            spent?: true,
            timestamp: ~U[2022-11-14 14:54:12Z]
          }
        }
      ]

      {:ok, pid1} = InputsWriter.start_link(:UCO, address)
      Enum.each(inputs, &InputsWriter.append_input(pid1, &1))

      assert ^inputs = InputsReader.get_inputs(:UCO, address)
      assert [] = InputsReader.get_inputs(:UCO, address2)
      assert [] = InputsReader.get_inputs(:UCO, address3)
    end

    test "returns the TOKEN inputs that were appended" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      address2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      address3 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      token_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      inputs = [
        %VersionedTransactionInput{
          protocol_version: 1,
          input: %TransactionInput{
            amount: 1,
            type: {:token, token_address, 0},
            from: address2,
            reward?: true,
            spent?: true,
            timestamp: ~U[2022-11-14 14:54:12Z]
          }
        },
        %VersionedTransactionInput{
          protocol_version: 1,
          input: %TransactionInput{
            amount: 2,
            type: {:token, token_address, 0},
            from: address3,
            reward?: true,
            spent?: true,
            timestamp: ~U[2022-11-14 14:54:12Z]
          }
        }
      ]

      {:ok, pid1} = InputsWriter.start_link(:token, address)
      Enum.each(inputs, &InputsWriter.append_input(pid1, &1))

      assert ^inputs = InputsReader.get_inputs(:token, address)
      assert [] = InputsReader.get_inputs(:token, address2)
      assert [] = InputsReader.get_inputs(:token, address3)
    end
  end
end
