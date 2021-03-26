defmodule Uniris.SharedSecrets.MemTablesLoaderTest do
  use ExUnit.Case

  alias Uniris.Crypto

  alias Uniris.SharedSecrets.MemTables.NetworkLookup
  alias Uniris.SharedSecrets.MemTables.OriginKeyLookup
  alias Uniris.SharedSecrets.MemTablesLoader

  alias Uniris.TransactionChain.MemTables.ChainLookup
  alias Uniris.TransactionChain.MemTables.KOLedger
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    start_supervised!(NetworkLookup)
    start_supervised!(OriginKeyLookup)
    start_supervised!(ChainLookup)
    start_supervised!(KOLedger)
    :ok
  end

  describe "load_transaction/1" do
    test "should load node transaction and first node public key as origin key" do
      tx = %Transaction{previous_public_key: "Node0", type: :node}
      assert :ok = MemTablesLoader.load_transaction(tx)

      assert ["Node0"] == OriginKeyLookup.list_public_keys()
    end

    test "should load transaction but node add node public key as origin key (already existing)" do
      ChainLookup.reverse_link(Crypto.hash("Node1"), "Node0", DateTime.utc_now())
      tx = %Transaction{previous_public_key: "Node0", type: :node}
      :ok = MemTablesLoader.load_transaction(tx)

      tx = %Transaction{previous_public_key: "Node1", type: :node}
      assert :ok = MemTablesLoader.load_transaction(tx)

      assert ["Node0"] == OriginKeyLookup.list_public_keys()
    end

    test "should load origin shared secret transaction and load keys from content" do
      tx = %Transaction{
        type: :origin_shared_secrets,
        data: %TransactionData{
          content: """
          software: 2C6D37F828E344F801221FAC4B03F40B3AF5AAF646CCF20C0E24F8F047DAF54E
          biometric: 27672633479F4A217A869993CA42E5D58C81BA9CBD27A8815EA18502B1B09EF6
          """
        }
      }

      assert :ok = MemTablesLoader.load_transaction(tx)

      assert [
               <<39, 103, 38, 51, 71, 159, 74, 33, 122, 134, 153, 147, 202, 66, 229, 213, 140,
                 129, 186, 156, 189, 39, 168, 129, 94, 161, 133, 2, 177, 176, 158, 246>>,
               <<44, 109, 55, 248, 40, 227, 68, 248, 1, 34, 31, 172, 75, 3, 244, 11, 58, 245, 170,
                 246, 70, 204, 242, 12, 14, 36, 248, 240, 71, 218, 245, 78>>
             ] == OriginKeyLookup.list_public_keys()

      assert [
               <<39, 103, 38, 51, 71, 159, 74, 33, 122, 134, 153, 147, 202, 66, 229, 213, 140,
                 129, 186, 156, 189, 39, 168, 129, 94, 161, 133, 2, 177, 176, 158, 246>>
             ] == OriginKeyLookup.list_public_keys(:biometric)
    end

    test "should load node shared secrets transaction and load public keys and address from content" do
      tx = %Transaction{
        type: :node_shared_secrets,
        data: %TransactionData{
          content:
            "daily nonce public_key: 009848F36BA37DE3B7A545EF793926EBDB7FBEC137E9D6FBB49A4349AE90A97DC3\nnetwork pool address: 008676C004975D50724E60682A714C168E4F8AA99F5D50F6413BABB6DF6003AA12\n"
        }
      }

      assert :ok = MemTablesLoader.load_transaction(tx)

      assert NetworkLookup.get_daily_nonce_public_key() |> Base.encode16() ==
               "009848F36BA37DE3B7A545EF793926EBDB7FBEC137E9D6FBB49A4349AE90A97DC3"

      assert NetworkLookup.get_network_pool_address() |> Base.encode16() ==
               "008676C004975D50724E60682A714C168E4F8AA99F5D50F6413BABB6DF6003AA12"
    end
  end

  describe "start_link/1" do
    test "should load transactions from database and fill the origin key lookup table" do
      ChainLookup.add_transaction_by_type(
        "@OriginSharedSecrets1",
        :origin_shared_secrets,
        DateTime.utc_now()
      )

      ChainLookup.add_transaction_by_type("@Node1", :node, DateTime.utc_now())

      origin_shared_secrets_tx = %Transaction{
        type: :origin_shared_secrets,
        data: %TransactionData{
          content: """
          software: 2C6D37F828E344F801221FAC4B03F40B3AF5AAF646CCF20C0E24F8F047DAF54E
          biometric: 27672633479F4A217A869993CA42E5D58C81BA9CBD27A8815EA18502B1B09EF6
          """
        }
      }

      node_tx = %Transaction{previous_public_key: "Node0", type: :node}

      MockDB
      |> stub(:get_transaction, fn
        "@Node1", _ ->
          {:ok, node_tx}

        "@OriginSharedSecrets1", _ ->
          {:ok, origin_shared_secrets_tx}
      end)

      assert {:ok, _} = MemTablesLoader.start_link()

      assert [
               "Node0",
               <<39, 103, 38, 51, 71, 159, 74, 33, 122, 134, 153, 147, 202, 66, 229, 213, 140,
                 129, 186, 156, 189, 39, 168, 129, 94, 161, 133, 2, 177, 176, 158, 246>>,
               <<44, 109, 55, 248, 40, 227, 68, 248, 1, 34, 31, 172, 75, 3, 244, 11, 58, 245, 170,
                 246, 70, 204, 242, 12, 14, 36, 248, 240, 71, 218, 245, 78>>
             ] == OriginKeyLookup.list_public_keys()
    end
  end
end
