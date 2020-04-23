defmodule UnirisCore.BootstrapTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.Crypto
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.Storage
  alias UnirisCore.Bootstrap
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node

  import Mox

  setup :set_mox_global

  setup_all do
    {:ok, %{seeds_file: Application.app_dir(:uniris_core, "priv/p2p/seeds")}}
  end

  describe "run/4" do
    test "network initialization when the first seed node is the equal to the first node public key",
         %{seeds_file: seeds_file} do
      me = self()

      MockStorage
      |> stub(:get_last_node_shared_secrets_transaction, fn ->
        {:error, :transaction_not_exists}
      end)
      |> stub(:write_transaction, fn tx ->
        send(me, tx)
        :ok
      end)
      |> stub(:get_transaction, fn _ ->
        {:error, :transaction_not_exists}
      end)
      |> stub(:node_transactions, fn -> [] end)

      File.write(seeds_file, "127.0.0.1:3002:#{Base.encode16(Crypto.node_public_key(0))}")

      Bootstrap.run({127, 0, 0, 1}, 3000, DateTime.utc_now(), seeds_file)

      receive do
        %Transaction{data: %TransactionData{keys: %{authorized_keys: auth_keys}}} ->
          assert Map.has_key?(auth_keys, Crypto.node_public_key(0))
      end
    end

    test "first node initialization", %{seeds_file: seeds_file} do
      File.write(
        seeds_file,
        "127.0.0.1:3002:00DCCD6E04C2DE94C2A461749E92B58AA618A4564582F513CB13A30213A0CD09C8"
      )

      MockNodeClient
      |> stub(:send_message, fn _, msg ->
        case msg do
          [{:closest_nodes, _}, :new_seeds] ->
            [
              [
                %Node{
                  ip: {127, 0, 0, 1},
                  port: 3000,
                  last_public_key: <<0>> <> :crypto.strong_rand_bytes(32),
                  first_public_key: <<0>> <> :crypto.strong_rand_bytes(32),
                  geo_patch: "AAA",
                  network_patch: "AAA",
                  ready?: true,
                  authorized?: true,
                  availability: 1
                }
              ],
              [
                %Node{
                  ip: {127, 0, 0, 1},
                  port: 3000,
                  last_public_key: <<0>> <> :crypto.strong_rand_bytes(32),
                  first_public_key: <<0>> <> :crypto.strong_rand_bytes(32),
                  geo_patch: "BBB",
                  network_patch: "BBB",
                  ready?: true,
                  authorized?: true,
                  availability: 1
                }
              ]
            ]

          {:new_transaction, tx} ->
            Storage.write_transaction(tx)
            :ok

          {:get_storage_nonce, _} ->
            {:ok, Crypto.ec_encrypt(:crypto.strong_rand_bytes(32), Crypto.node_public_key())}

          :list_nodes ->
            []

          {:get_beacon_slots, _, _} ->
            []

          {:add_node_info, _, _info} ->
            :ok
        end
      end)

      MockStorage
      |> stub(:get_last_node_shared_secrets_transaction, fn ->
        {:error, :transaction_not_exists}
      end)
      |> stub(:write_transaction_chain, fn _ -> :ok end)
      |> stub(:write_transaction, fn tx ->
        P2P.add_node(%Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key: tx.previous_public_key,
          first_public_key: tx.previous_public_key
        })

        :ok
      end)
      |> stub(:get_transaction, fn _ ->
        {:ok, ""}
      end)

      Bootstrap.run({127, 0, 0, 1}, 3000, DateTime.utc_now(), seeds_file)
    end
  end
end
