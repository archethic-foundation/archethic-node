defmodule Uniris.OracleChain.MemTableLoaderTest do
  use UnirisCase

  alias Uniris.OracleChain.MemTable
  alias Uniris.OracleChain.MemTableLoader

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData

  describe "load_transaction/1" do
    test "should load an oracle transaction into the mem table" do
      assert :ok =
               MemTableLoader.load_transaction(%Transaction{
                 type: :oracle,
                 data: %TransactionData{
                   content: %{"uco" => %{"eur" => 0.02}} |> Jason.encode!()
                 },
                 validation_stamp: %ValidationStamp{
                   timestamp: DateTime.utc_now()
                 }
               })

      assert {:ok, %{"eur" => 0.02}} = MemTable.get_oracle_data("uco", DateTime.utc_now())
    end

    test "should load an oracle summary transaction and the related changes" do
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

      assert {:ok, %{"eur" => 0.07}} =
               MemTable.get_oracle_data("uco", DateTime.from_unix!(1_614_677_925))
    end
  end
end
