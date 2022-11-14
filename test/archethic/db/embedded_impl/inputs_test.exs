defmodule Archethic.DB.EmbeddedImpl.InputsTest do
  use ArchethicCase

  alias Archethic.DB.EmbeddedImpl.Inputs

  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.TransactionInput

  setup do
    db_path = Application.app_dir(:archethic, "data_test")
    File.mkdir_p!(db_path)

    {:ok, _} = Inputs.start_link(path: db_path)

    on_exit(fn ->
      File.rm_rf!(db_path)
    end)

    %{db_path: db_path}
  end

  describe "Append/Get" do
    test "returns empty when there is none", %{db_path: db_path} do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      assert [] = Inputs.get_inputs(address)
    end

    test "returns the inputs that were appended", %{db_path: db_path} do
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
            timestamp: DateTime.utc_now()
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
            timestamp: DateTime.utc_now()
          }
        }
      ]

      Inputs.append_inputs(inputs, address)
      assert inputs = Inputs.get_inputs(address)
      assert [] = Inputs.get_inputs(address2)
      assert [] = Inputs.get_inputs(address3)
    end
  end
end
