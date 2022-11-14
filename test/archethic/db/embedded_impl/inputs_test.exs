defmodule Archethic.DB.EmbeddedImpl.InputsTest do
  use ArchethicCase

  alias Archethic.DB.EmbeddedImpl.Inputs

  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.TransactionInput

  setup do
    db_path = Application.app_dir(:archethic, "data_test")
    File.mkdir_p!(db_path)

    on_exit(fn ->
      File.rm_rf!(db_path)
    end)

    %{db_path: db_path}
  end

  describe "Append/Get" do
    test "returns empty when there is none" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      assert [] = Inputs.get_inputs(:UCO, address)
      assert [] = Inputs.get_inputs(:token, address)
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

      Inputs.append_inputs(:UCO, inputs, address)
      assert ^inputs = Inputs.get_inputs(:UCO, address)
      assert [] = Inputs.get_inputs(:UCO, address2)
      assert [] = Inputs.get_inputs(:UCO, address3)
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

      Inputs.append_inputs(:token, inputs, address)
      assert ^inputs = Inputs.get_inputs(:token, address)
      assert [] = Inputs.get_inputs(:token, address2)
      assert [] = Inputs.get_inputs(:token, address3)
    end
  end
end
