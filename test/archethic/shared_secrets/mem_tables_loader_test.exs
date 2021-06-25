defmodule ArchEthic.SharedSecrets.MemTablesLoaderTest do
  use ArchEthicCase, async: false

  alias ArchEthic.Bootstrap.NetworkInit
  alias ArchEthic.Crypto

  alias ArchEthic.SharedSecrets.MemTables.NetworkLookup
  alias ArchEthic.SharedSecrets.MemTables.OriginKeyLookup
  alias ArchEthic.SharedSecrets.MemTablesLoader
  alias ArchEthic.SharedSecrets.NodeRenewalScheduler

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.TransactionData

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  describe "load_transaction/1" do
    test "should load node transaction and first node public key as origin key" do
      first_public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      MockDB
      |> expect(:get_first_public_key, fn _ -> first_public_key end)

      tx = %Transaction{previous_public_key: first_public_key, type: :node}
      assert :ok = MemTablesLoader.load_transaction(tx)

      assert [first_public_key] == OriginKeyLookup.list_public_keys()
    end

    test "should load transaction but node add node public key as origin key (already existing)" do
      first_public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      second_public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      MockDB
      |> stub(:get_first_public_key, fn _ -> first_public_key end)

      tx = %Transaction{previous_public_key: first_public_key, type: :node}
      :ok = MemTablesLoader.load_transaction(tx)

      tx = %Transaction{previous_public_key: second_public_key, type: :node}
      assert :ok = MemTablesLoader.load_transaction(tx)

      assert [first_public_key] == OriginKeyLookup.list_public_keys()
    end

    test "should load origin shared secret transaction and load keys from content" do
      tx = %Transaction{
        type: :origin_shared_secrets,
        data: %TransactionData{
          content:
            <<0, 1, 39, 103, 38, 51, 71, 159, 74, 33, 122, 134, 153, 147, 202, 66, 229, 213, 140,
              129, 186, 156, 39, 168, 129, 94, 161, 133, 2, 177, 176, 158, 246, 10, 0, 0, 44, 109,
              55, 248, 40, 227, 68, 248, 1, 34, 31, 172, 75, 3, 244, 11, 58, 245, 170, 246, 70,
              204, 242, 12, 14, 36, 248, 240, 71, 218, 245, 78>>
        }
      }

      assert :ok = MemTablesLoader.load_transaction(tx)

      assert [
               <<0, 0, 44, 109, 55, 248, 40, 227, 68, 248, 1, 34, 31, 172, 75, 3, 244, 11, 58,
                 245, 170, 246, 70, 204, 242, 12, 14, 36, 248, 240, 71, 218, 245, 78>>,
               <<0, 1, 39, 103, 38, 51, 71, 159, 74, 33, 122, 134, 153, 147, 202, 66, 229, 213,
                 140, 129, 186, 156, 39, 168, 129, 94, 161, 133, 2, 177, 176, 158, 246, 10>>
             ] == OriginKeyLookup.list_public_keys()

      assert [
               <<0, 1, 39, 103, 38, 51, 71, 159, 74, 33, 122, 134, 153, 147, 202, 66, 229, 213,
                 140, 129, 186, 156, 39, 168, 129, 94, 161, 133, 2, 177, 176, 158, 246, 10>>
             ] == OriginKeyLookup.list_public_keys(:hardware)
    end

    test "should load node shared secrets transaction and load public keys and address from content" do
      tx = %Transaction{
        type: :node_shared_secrets,
        data: %TransactionData{
          content:
            <<0, 0, 134, 118, 192, 4, 151, 93, 80, 114, 78, 96, 104, 42, 113, 76, 22, 142, 79,
              138, 169, 159, 93, 80, 246, 65, 59, 171, 182, 223, 96, 3, 170, 1, 0, 134, 118, 192,
              4, 151, 93, 80, 114, 78, 96, 104, 42, 113, 76, 22, 142, 79, 138, 169, 159, 93, 80,
              246, 65, 59, 171, 182, 223, 96, 3, 170, 18>>
        },
        validation_stamp: %ValidationStamp{
          timestamp: DateTime.utc_now() |> DateTime.add(10)
        }
      }

      assert :ok = MemTablesLoader.load_transaction(tx)

      genesis_daily_nonce_public_key =
        :archethic
        |> Application.get_env(NetworkInit)
        |> Keyword.fetch!(:genesis_daily_nonce_seed)
        |> Crypto.generate_deterministic_keypair()
        |> elem(0)

      assert NetworkLookup.get_daily_nonce_public_key() ==
               genesis_daily_nonce_public_key

      assert NetworkLookup.get_daily_nonce_public_key(DateTime.utc_now()) ==
               genesis_daily_nonce_public_key

      assert NetworkLookup.get_daily_nonce_public_key(
               NodeRenewalScheduler.next_application_date(DateTime.utc_now())
             )

      assert NetworkLookup.get_network_pool_address() ==
               <<0, 134, 118, 192, 4, 151, 93, 80, 114, 78, 96, 104, 42, 113, 76, 22, 142, 79,
                 138, 169, 159, 93, 80, 246, 65, 59, 171, 182, 223, 96, 3, 170, 18>>
    end
  end

  describe "start_link/1" do
    test "should load transactions from database and fill the lookup table" do
      origin_shared_secrets_tx = %Transaction{
        type: :origin_shared_secrets,
        data: %TransactionData{
          content:
            <<0, 1, 39, 103, 38, 51, 71, 159, 74, 33, 122, 134, 153, 147, 202, 66, 229, 213, 140,
              129, 186, 156, 39, 168, 129, 94, 161, 133, 2, 177, 176, 158, 246, 10, 0, 0, 44, 109,
              55, 248, 40, 227, 68, 248, 1, 34, 31, 172, 75, 3, 244, 11, 58, 245, 170, 246, 70,
              204, 242, 12, 14, 36, 248, 240, 71, 218, 245, 78>>
        }
      }

      node_tx = %Transaction{
        previous_public_key:
          <<0, 0, 174, 5, 254, 137, 242, 45, 117, 124, 241, 11, 154, 120, 62, 254, 137, 49, 24,
            186, 216, 182, 81, 64, 93, 92, 48, 231, 23, 124, 127, 140, 103, 105>>,
        type: :node
      }

      node_shared_secrets_tx = %Transaction{
        type: :node_shared_secrets,
        data: %TransactionData{
          content:
            <<0, 0, 134, 118, 192, 4, 151, 93, 80, 114, 78, 96, 104, 42, 113, 76, 22, 142, 79,
              138, 169, 159, 93, 80, 246, 65, 59, 171, 182, 223, 96, 3, 170, 18, 0, 134, 118, 192,
              4, 151, 93, 80, 114, 78, 96, 104, 42, 113, 76, 22, 142, 79, 138, 169, 159, 93, 80,
              246, 65, 59, 171, 182, 223, 96, 3, 170, 18>>
        },
        validation_stamp: %ValidationStamp{
          timestamp: DateTime.utc_now() |> DateTime.add(10)
        }
      }

      MockDB
      |> stub(:list_transactions_by_type, fn
        :node, _ ->
          [node_tx]

        :origin_shared_secrets, _ ->
          [origin_shared_secrets_tx]

        :node_shared_secrets, _ ->
          [node_shared_secrets_tx]
      end)
      |> expect(:get_first_public_key, fn _ ->
        <<0, 0, 174, 5, 254, 137, 242, 45, 117, 124, 241, 11, 154, 120, 62, 254, 137, 49, 24, 186,
          216, 182, 81, 64, 93, 92, 48, 231, 23, 124, 127, 140, 103, 105>>
      end)

      assert {:ok, _} = MemTablesLoader.start_link()

      assert [
               <<0, 0, 44, 109, 55, 248, 40, 227, 68, 248, 1, 34, 31, 172, 75, 3, 244, 11, 58,
                 245, 170, 246, 70, 204, 242, 12, 14, 36, 248, 240, 71, 218, 245, 78>>,
               <<0, 0, 174, 5, 254, 137, 242, 45, 117, 124, 241, 11, 154, 120, 62, 254, 137, 49,
                 24, 186, 216, 182, 81, 64, 93, 92, 48, 231, 23, 124, 127, 140, 103, 105>>,
               <<0, 1, 39, 103, 38, 51, 71, 159, 74, 33, 122, 134, 153, 147, 202, 66, 229, 213,
                 140, 129, 186, 156, 39, 168, 129, 94, 161, 133, 2, 177, 176, 158, 246, 10>>
             ] == OriginKeyLookup.list_public_keys()

      genesis_daily_nonce_public_key =
        :archethic
        |> Application.get_env(NetworkInit)
        |> Keyword.fetch!(:genesis_daily_nonce_seed)
        |> Crypto.generate_deterministic_keypair()
        |> elem(0)

      assert NetworkLookup.get_daily_nonce_public_key(DateTime.utc_now()) ==
               genesis_daily_nonce_public_key

      assert NetworkLookup.get_daily_nonce_public_key(
               NodeRenewalScheduler.next_application_date(
                 node_shared_secrets_tx.validation_stamp.timestamp
               )
             ) ==
               <<0, 0, 134, 118, 192, 4, 151, 93, 80, 114, 78, 96, 104, 42, 113, 76, 22, 142, 79,
                 138, 169, 159, 93, 80, 246, 65, 59, 171, 182, 223, 96, 3, 170, 18>>
    end
  end
end
