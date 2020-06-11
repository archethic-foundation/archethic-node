defmodule UnirisCore.BootstrapTest do
  use UnirisCoreCase

  alias UnirisCore.Crypto
  alias UnirisCore.Storage
  alias UnirisCore.Bootstrap
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.BeaconSlotTimer
  alias UnirisCore.BeaconSubsets
  alias UnirisCore.BeaconSubset
  alias UnirisCore.Transaction
  alias UnirisCore.SelfRepair
  alias UnirisCore.Bootstrap.NetworkInit
  alias UnirisCore.P2P.BootstrapingSeeds

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    Enum.each(BeaconSubsets.all(), &BeaconSubset.start_link(subset: &1))
    start_supervised!({BeaconSlotTimer, interval: 1_000, trigger_offset: 0})
    start_supervised!({SelfRepair, interval: 0, last_sync_file: "priv/p2p/last_sync"})
    start_supervised!(BootstrapingSeeds)

    on_exit(fn ->
      File.rm(Application.app_dir(:uniris_core, "priv/p2p/last_sync"))
    end)
  end

  describe "run/4" do
    test "network initialization when the first seed node is the equal to the first node public key" do
      MockStorage
      |> stub(:write_transaction_chain, fn [tx | _] ->
        case tx do
          %Transaction{type: :node} ->
            P2P.add_node(%Node{
              ip: {127, 0, 0, 1},
              port: 3002,
              first_public_key: Crypto.node_public_key(0),
              last_public_key: Crypto.node_public_key(0),
              enrollment_date: DateTime.utc_now(),
              authorized?: true
            })

          _ ->
            :ok
        end
      end)

      Bootstrap.run({127, 0, 0, 1}, 3000, DateTime.utc_now(), [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: Crypto.node_public_key(0),
          last_public_key: Crypto.node_public_key(0)
        }
      ])

      assert [%Node{ip: {127, 0, 0, 1}, authorized?: true}] = P2P.list_nodes()
    end

    test "first node initialization" do
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
            Storage.write_transaction_chain([tx |> NetworkInit.self_validation!()])
            :ok

          {:get_storage_nonce, _} ->
            {:ok, Crypto.ec_encrypt(:crypto.strong_rand_bytes(32), Crypto.node_public_key())}

          :list_nodes ->
            []

          {:get_beacon_slots, _} ->
            []

          {:add_node_info, _, _info} ->
            send(me, :node_ready)
            :ok
        end
      end)

      MockStorage
      |> stub(:write_transaction_chain, fn [
                                             %Transaction{
                                               type: :node,
                                               previous_public_key: previous_public_key
                                             }
                                           ] ->
        P2P.add_node(%Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key: previous_public_key,
          first_public_key: previous_public_key,
          enrollment_date: DateTime.utc_now()
        })

        :ok
      end)

      Bootstrap.run({127, 0, 0, 1}, 3000, DateTime.utc_now(), [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: :crypto.strong_rand_bytes(32),
          last_public_key: :crypto.strong_rand_bytes(32)
        }
      ])

      assert_received :node_ready
    end

    test "update node" do
      me = self()

      MockStorage
      |> stub(:write_transaction_chain, fn [
                                             %Transaction{
                                               type: :node,
                                               previous_public_key: previous_public_key
                                             }
                                           ] ->
        case P2P.node_info() do
          {:error, :not_found} ->
            P2P.add_node(%Node{
              ip: {127, 0, 0, 1},
              port: 3000,
              last_public_key: previous_public_key,
              first_public_key: previous_public_key,
              enrollment_date: DateTime.utc_now()
            })

          {:ok, %Node{first_public_key: first_public_key}} ->
            Node.update_basics(first_public_key, previous_public_key, {200, 50, 20, 10}, 3000)
        end

        Crypto.increment_number_of_generate_node_keys()

        :ok
      end)

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
            Storage.write_transaction_chain([tx |> NetworkInit.self_validation!()])
            :ok

          {:get_storage_nonce, _} ->
            {:ok, Crypto.ec_encrypt(:crypto.strong_rand_bytes(32), Crypto.node_public_key())}

          :list_nodes ->
            []

          {:get_beacon_slots, _} ->
            []

          {:add_node_info, _, _info} ->
            send(me, :node_ready)
            :ok
        end
      end)

      {:ok, counter} = Agent.start_link(fn -> 0 end)

      MockCrypto
      |> stub(:increment_number_of_generate_node_keys, fn ->
        Agent.update(counter, &(&1 + 1))
      end)
      |> stub(:number_of_node_keys, fn ->
        Agent.get(counter, & &1)
      end)

      Bootstrap.run({127, 0, 0, 1}, 3000, DateTime.utc_now(), [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: :crypto.strong_rand_bytes(32),
          last_public_key: :crypto.strong_rand_bytes(32)
        }
      ])

      assert_received :node_ready

      Bootstrap.run({200, 50, 20, 10}, 3000, DateTime.utc_now(), [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: :crypto.strong_rand_bytes(32),
          last_public_key: :crypto.strong_rand_bytes(32)
        }
      ])

      Process.sleep(1000)

      {:ok,
       %Node{
         ip: {200, 50, 20, 10},
         first_public_key: first_public_key,
         last_public_key: last_public_key
       }} = P2P.node_info()

      assert first_public_key == Crypto.node_public_key(0)
      assert last_public_key == Crypto.node_public_key(1)
    end
  end
end
