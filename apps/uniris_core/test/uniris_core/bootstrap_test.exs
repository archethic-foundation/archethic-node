defmodule UnirisCore.BootstrapTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.Crypto
  alias UnirisCore.Storage
  alias UnirisCore.Bootstrap
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.BeaconSlotTimer
  alias UnirisCore.BeaconSubsets
  alias UnirisCore.BeaconSubset

  import Mox

  setup :set_mox_global

  setup_all do
    {:ok, %{seeds_file: Application.app_dir(:uniris_core, "priv/p2p/test_seeds")}}

    on_exit fn ->
      File.rm(Application.app_dir(:uniris_core, "priv/p2p/test_seeds"))
    end
  end

  setup do
    start_supervised!(UnirisCore.Storage.Cache)
    start_supervised!({UnirisCore.SelfRepair, interval: 10_000})
    start_supervised!({BeaconSlotTimer, slot_interval: 10_000})
    Enum.each(BeaconSubsets.all(), &start_supervised!({BeaconSubset, subset: &1}, id: &1))
    :ok
  end

  describe "run/4" do
    test "network initialization when the first seed node is the equal to the first node public key",
         %{seeds_file: seeds_file} do
      MockStorage
      |> stub(:write_transaction, fn _tx ->
        P2P.add_node(%Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          first_public_key: Crypto.node_public_key(0),
          last_public_key: Crypto.node_public_key(0),
          enrollment_date: DateTime.utc_now(),
          authorized?: true
        })

        :ok
      end)

      File.write(seeds_file, "127.0.0.1:3002:#{Base.encode16(Crypto.node_public_key(0))}")

      Bootstrap.run({127, 0, 0, 1}, 3000, DateTime.utc_now(), seeds_file)

      assert [%Node{ip: {127, 0, 0, 1}}] = P2P.list_nodes()
    end

    test "first node initialization", %{seeds_file: seeds_file} do
      File.write(
        seeds_file,
        "127.0.0.1:3002:00DCCD6E04C2DE94C2A461749E92B58AA618A4564582F513CB13A30213A0CD09C8"
      )

      me = self()

      MockNodeClient
      |> stub(:send_message, fn _, _, msg ->
        case msg do
          [{:closest_nodes, _}, :new_seeds] ->
            [
              [
                %Node{
                  ip: {127, 0, 0, 1},
                  port: 3000,
                  last_public_key:
                    <<0, 220, 205, 110, 4, 194, 222, 148, 194, 164, 97, 116, 158, 146, 181, 138,
                      166, 24, 164, 86, 69, 130, 245, 19, 203, 19, 163, 2, 19, 160, 205, 9, 200>>,
                  first_public_key:
                    <<0, 220, 205, 110, 4, 194, 222, 148, 194, 164, 97, 116, 158, 146, 181, 138,
                      166, 24, 164, 86, 69, 130, 245, 19, 203, 19, 163, 2, 19, 160, 205, 9, 200>>,
                  geo_patch: "AAA",
                  network_patch: "AAA",
                  ready?: true,
                  ready_date: DateTime.utc_now(),
                  authorized?: true,
                  authorization_date: DateTime.utc_now(),
                  available?: true,
                  enrollment_date: DateTime.utc_now()
                }
              ],
              [
                %Node{
                  ip: {127, 0, 0, 1},
                  port: 3000,
                  last_public_key:
                    <<0, 186, 140, 57, 71, 50, 47, 229, 252, 24, 60, 6, 188, 83, 193, 145, 249,
                      111, 74, 30, 113, 111, 191, 242, 155, 199, 104, 181, 21, 95, 208, 108,
                      146>>,
                  first_public_key:
                    <<0, 186, 140, 57, 71, 50, 47, 229, 252, 24, 60, 6, 188, 83, 193, 145, 249,
                      111, 74, 30, 113, 111, 191, 242, 155, 199, 104, 181, 21, 95, 208, 108,
                      146>>,
                  geo_patch: "BBB",
                  network_patch: "BBB",
                  ready?: true,
                  ready_date: DateTime.utc_now(),
                  authorized?: true,
                  authorization_date: DateTime.utc_now(),
                  available?: true,
                  enrollment_date: DateTime.utc_now()
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
            send(me, :node_ready)
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
          first_public_key: tx.previous_public_key,
          enrollment_date: DateTime.utc_now()
        })

        :ok
      end)
      |> stub(:get_transaction, fn _ ->
        {:ok, ""}
      end)

      Bootstrap.run({127, 0, 0, 1}, 3000, DateTime.utc_now(), seeds_file)

      assert_received :node_ready
    end
  end
end
