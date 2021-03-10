defmodule Uniris.OracleChain.MemTableLoaderTest do
  use UnirisCase

  alias Uniris.OracleChain.MemTable
  alias Uniris.OracleChain.MemTableLoader

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  describe "load_transaction/1" do
    test "should load an oracle transaction into the mem table" do
      {:ok, _} = MemTable.start_link()

      assert :ok =
               MemTableLoader.load_transaction(%Transaction{
                 type: :oracle,
                 data: %TransactionData{
                   content: %{"uco" => %{"eur" => 0.02}} |> Jason.encode!()
                 }
               })

      assert {:ok, %{"eur" => 0.02}} = MemTable.get_oracle_data("uco")
    end

    test "should load an oracle summary transaction and the related changes" do
      {:ok, _} = MemTable.start_link()

      assert :ok =
               MemTableLoader.load_transaction(%Transaction{
                 type: :oracle_summary,
                 data: %TransactionData{
                   content:
                     %{
                       "1614677930" => %{
                         "uco" => %{"eur" => 0.02}
                       },
                       "1614677925" => %{
                         "uco" => %{"eur" => 0.07}
                       }
                     }
                     |> Jason.encode!()
                 }
               })

      assert {:ok, %{"eur" => 0.02}} = MemTable.get_oracle_data("uco")
    end
  end
end
