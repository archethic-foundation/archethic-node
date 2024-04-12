defmodule Archethic.SharedSecrets.MemTablesLoaderTest do
  use ArchethicCase, async: false

  alias Archethic.Bootstrap.NetworkInit
  alias Archethic.Crypto

  alias Archethic.P2P.Node

  alias Archethic.SharedSecrets.MemTables.NetworkLookup
  alias Archethic.SharedSecrets.MemTables.OriginKeyLookup
  alias Archethic.SharedSecrets.MemTablesLoader
  alias Archethic.SharedSecrets.NodeRenewalScheduler

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  @origin_genesis_public_keys Application.compile_env(:archethic, [
                                NetworkInit,
                                :genesis_origin_public_keys
                              ])

  @genesis_daily_nonce_public_key Application.compile_env!(:archethic, [
                                    NetworkInit,
                                    :genesis_daily_nonce_seed
                                  ])
                                  |> Crypto.generate_deterministic_keypair()
                                  |> elem(0)

  describe "load_transaction/1" do
    test "should load node transaction and extract origin public key from the tx's content" do
      origin_public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      tx = %Transaction{
        type: :node,
        data: %TransactionData{
          content:
            Node.encode_transaction_content(
              {127, 0, 0, 1},
              3000,
              4000,
              :tcp,
              <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
              origin_public_key,
              :crypto.strong_rand_bytes(64)
            )
        }
      }

      assert :ok = MemTablesLoader.load_transaction(tx)

      expected_keys = [origin_public_key] ++ @origin_genesis_public_keys
      assert Enum.all?(OriginKeyLookup.list_public_keys(), &(&1 in expected_keys))
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

      expected_keys = [first_public_key] ++ @origin_genesis_public_keys
      assert Enum.all?(OriginKeyLookup.list_public_keys(), &(&1 in expected_keys))
    end

    test "should load origin transaction and load keys from content" do
      tx = %Transaction{
        type: :origin,
        data: %TransactionData{
          content:
            <<0, 2, 39, 103, 38, 51, 71, 159, 74, 33, 122, 134, 153, 147, 202, 66, 229, 213, 140,
              129, 186, 156, 39, 168, 129, 94, 161, 133, 2, 177, 176, 158, 246, 10, 0, 0, 44, 109,
              55, 248, 40, 227, 68, 248, 1, 34, 31, 172, 75, 3, 244, 11, 58, 245, 170, 246, 70,
              204, 242, 12, 14, 36, 248, 240, 71, 218, 245, 78>>
        }
      }

      assert :ok = MemTablesLoader.load_transaction(tx)

      expected_keys =
        [
          <<0, 0, 44, 109, 55, 248, 40, 227, 68, 248, 1, 34, 31, 172, 75, 3, 244, 11, 58, 245,
            170, 246, 70, 204, 242, 12, 14, 36, 248, 240, 71, 218, 245, 78>>,
          <<0, 2, 39, 103, 38, 51, 71, 159, 74, 33, 122, 134, 153, 147, 202, 66, 229, 213, 140,
            129, 186, 156, 39, 168, 129, 94, 161, 133, 2, 177, 176, 158, 246, 10>>
        ] ++ @origin_genesis_public_keys

      assert Enum.all?(OriginKeyLookup.list_public_keys(), &(&1 in expected_keys))

      assert [
               <<0, 2, 39, 103, 38, 51, 71, 159, 74, 33, 122, 134, 153, 147, 202, 66, 229, 213,
                 140, 129, 186, 156, 39, 168, 129, 94, 161, 133, 2, 177, 176, 158, 246, 10>>
             ] == OriginKeyLookup.list_public_keys(:hardware)
    end

    test "should load node shared secrets transaction and load public keys and address from content" do
      tx = %Transaction{
        type: :node_shared_secrets,
        data: %TransactionData{
          content:
            <<0, 0, 134, 118, 192, 4, 151, 93, 80, 114, 78, 96, 104, 42, 113, 76, 22, 142, 79,
              138, 169, 159, 93, 80, 246, 65, 59, 171, 182, 223, 96, 3, 170, 1, 0, 0, 134, 118,
              192, 4, 151, 93, 80, 114, 78, 96, 104, 42, 113, 76, 22, 142, 79, 138, 169, 159, 93,
              80, 246, 65, 59, 171, 182, 223, 96, 3, 170, 18>>
        },
        validation_stamp: %ValidationStamp{
          timestamp: DateTime.utc_now() |> DateTime.add(10)
        }
      }

      assert :ok = MemTablesLoader.load_transaction(tx)

      assert NetworkLookup.get_daily_nonce_public_key() ==
               @genesis_daily_nonce_public_key

      assert NetworkLookup.get_daily_nonce_public_key(DateTime.utc_now()) ==
               @genesis_daily_nonce_public_key

      assert NetworkLookup.get_daily_nonce_public_key(
               NodeRenewalScheduler.next_application_date(DateTime.utc_now())
             )
    end
  end

  describe "start_link/1" do
    test "should load transactions from database and fill the lookup table" do
      origin_tx = %Transaction{
        type: :origin,
        data: %TransactionData{
          content:
            <<0, 1, 39, 103, 38, 51, 71, 159, 74, 33, 122, 134, 153, 147, 202, 66, 229, 213, 140,
              129, 186, 156, 39, 168, 129, 94, 161, 133, 2, 177, 176, 158, 246, 10, 0, 0, 44, 109,
              55, 248, 40, 227, 68, 248, 1, 34, 31, 172, 75, 3, 244, 11, 58, 245, 170, 246, 70,
              204, 242, 12, 14, 36, 248, 240, 71, 218, 245, 78>>
        }
      }

      node_tx = %Transaction{
        type: :node,
        data: %TransactionData{
          content:
            Node.encode_transaction_content(
              {127, 0, 0, 1},
              3000,
              4000,
              :tcp,
              <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
              <<0, 0, 174, 5, 254, 137, 242, 45, 117, 124, 241, 11, 154, 120, 62, 254, 137, 49,
                24, 186, 216, 182, 81, 64, 93, 92, 48, 231, 23, 124, 127, 140, 103, 105>>,
              :crypto.strong_rand_bytes(32)
            )
        }
      }

      node_shared_secrets_tx = %Transaction{
        type: :node_shared_secrets,
        data: %TransactionData{
          content:
            <<0, 0, 134, 118, 192, 4, 151, 93, 80, 114, 78, 96, 104, 42, 113, 76, 22, 142, 79,
              138, 169, 159, 93, 80, 246, 65, 59, 171, 182, 223, 96, 3, 170, 18, 0, 0, 134, 118,
              192, 4, 151, 93, 80, 114, 78, 96, 104, 42, 113, 76, 22, 142, 79, 138, 169, 159, 93,
              80, 246, 65, 59, 171, 182, 223, 96, 3, 170, 18>>
        },
        validation_stamp: %ValidationStamp{
          timestamp: DateTime.utc_now() |> DateTime.add(10)
        }
      }

      MockDB
      |> stub(:list_transactions_by_type, fn
        :node, _ ->
          [node_tx]

        :origin, _ ->
          [origin_tx]

        :node_shared_secrets, _ ->
          [node_shared_secrets_tx]
      end)

      assert {:ok, _} = MemTablesLoader.start_link()

      expected_keys =
        [
          <<0, 0, 44, 109, 55, 248, 40, 227, 68, 248, 1, 34, 31, 172, 75, 3, 244, 11, 58, 245,
            170, 246, 70, 204, 242, 12, 14, 36, 248, 240, 71, 218, 245, 78>>,
          <<0, 0, 174, 5, 254, 137, 242, 45, 117, 124, 241, 11, 154, 120, 62, 254, 137, 49, 24,
            186, 216, 182, 81, 64, 93, 92, 48, 231, 23, 124, 127, 140, 103, 105>>,
          <<0, 1, 39, 103, 38, 51, 71, 159, 74, 33, 122, 134, 153, 147, 202, 66, 229, 213, 140,
            129, 186, 156, 39, 168, 129, 94, 161, 133, 2, 177, 176, 158, 246, 10>>
        ] ++ @origin_genesis_public_keys

      assert Enum.all?(OriginKeyLookup.list_public_keys(), &(&1 in expected_keys))

      assert NetworkLookup.get_daily_nonce_public_key(DateTime.utc_now()) ==
               @genesis_daily_nonce_public_key

      assert @genesis_daily_nonce_public_key ==
               DateTime.utc_now()
               |> NodeRenewalScheduler.next_application_date()
               |> NetworkLookup.get_daily_nonce_public_key()
    end
  end
end
