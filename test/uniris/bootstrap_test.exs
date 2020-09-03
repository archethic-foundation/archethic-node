defmodule Uniris.BootstrapTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.Beacon
  alias Uniris.BeaconSlotTimer
  alias Uniris.BeaconSubset

  alias Uniris.Bootstrap
  alias Uniris.Bootstrap.NetworkInit

  alias Uniris.P2P
  alias Uniris.P2P.BootstrapingSeeds
  alias Uniris.P2P.Message.AddNodeInfo
  alias Uniris.P2P.Message.BeaconSlotList
  alias Uniris.P2P.Message.BootstrappingNodes
  alias Uniris.P2P.Message.EncryptedStorageNonce
  alias Uniris.P2P.Message.GetBeaconSlots
  alias Uniris.P2P.Message.GetBootstrappingNodes
  alias Uniris.P2P.Message.GetStorageNonce
  alias Uniris.P2P.Message.ListNodes
  alias Uniris.P2P.Message.NewTransaction
  alias Uniris.P2P.Message.NodeList
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Node

  alias Uniris.SelfRepair

  alias Uniris.SharedSecretsRenewal

  alias Uniris.Storage
  alias Uniris.Storage.Memory.NetworkLedger

  alias Uniris.Transaction

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    me = self()

    MockNodeClient
    |> stub(:send_message, fn _, _, msg ->
      case msg do
        %GetBootstrappingNodes{} ->
          {:ok,
           %BootstrappingNodes{
             new_seeds: [
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
             closest_nodes: [
               %Node{
                 ip: {127, 0, 0, 1},
                 port: 3000,
                 last_public_key:
                   <<0, 186, 140, 57, 71, 50, 47, 229, 252, 24, 60, 6, 188, 83, 193, 145, 249,
                     111, 74, 30, 113, 111, 191, 242, 155, 199, 104, 181, 21, 95, 208, 108, 146>>,
                 first_public_key:
                   <<0, 186, 140, 57, 71, 50, 47, 229, 252, 24, 60, 6, 188, 83, 193, 145, 249,
                     111, 74, 30, 113, 111, 191, 242, 155, 199, 104, 181, 21, 95, 208, 108, 146>>,
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
           }}

        %NewTransaction{transaction: tx} ->
          Storage.write_transaction_chain([tx |> NetworkInit.self_validation!()])
          {:ok, %Ok{}}

        %GetStorageNonce{} ->
          {:ok,
           %EncryptedStorageNonce{
             digest: Crypto.ec_encrypt(:crypto.strong_rand_bytes(32), Crypto.node_public_key())
           }}

        %ListNodes{} ->
          {:ok, %NodeList{}}

        %GetBeaconSlots{} ->
          {:ok, %BeaconSlotList{}}

        %AddNodeInfo{} ->
          send(me, :node_ready)
          {:ok, %Ok{}}
      end
    end)

    :ok
  end

  setup do
    Enum.each(Beacon.list_subsets(), &BeaconSubset.start_link(subset: &1))
    start_supervised!({BeaconSlotTimer, interval: "* * * * * *", trigger_offset: 0})
    start_supervised!({SelfRepair, interval: "* * * * * *", last_sync_file: "priv/p2p/last_sync"})
    start_supervised!(BootstrapingSeeds)
    start_supervised!({SharedSecretsRenewal, interval: "* * * * * *", trigger_offset: 0})

    on_exit(fn ->
      File.rm(Application.app_dir(:uniris, "priv/p2p/last_sync"))
    end)
  end

  describe "run/4" do
    test "network initialization when the first seed node is the equal to the first node public key" do
      MockStorage
      |> stub(:write_transaction_chain, fn [tx | _] ->
        case tx do
          %Transaction{type: :node} ->
            NetworkLedger.add_node_info(%Node{
              ip: {127, 0, 0, 1},
              port: 3000,
              first_public_key: Crypto.node_public_key(0),
              last_public_key: Crypto.node_public_key(),
              enrollment_date: DateTime.utc_now(),
              authorized?: true
            })

          _ ->
            :ok
        end
      end)

      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: Crypto.node_public_key(0),
          last_public_key: Crypto.node_public_key()
        }
      ]

      Enum.each(seeds, &NetworkLedger.add_node_info/1)

      Bootstrap.run({127, 0, 0, 1}, 3000, DateTime.utc_now(), seeds)

      assert [%Node{ip: {127, 0, 0, 1}, authorized?: true}] = NetworkLedger.list_nodes()
    end

    test "first node initialization" do
      MockStorage
      |> stub(:write_transaction_chain, fn [
                                             %Transaction{
                                               type: :node,
                                               previous_public_key: previous_public_key
                                             }
                                           ] ->
        NetworkLedger.add_node_info(%Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key: previous_public_key,
          first_public_key: previous_public_key,
          enrollment_date: DateTime.utc_now()
        })

        :ok
      end)

      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: :crypto.strong_rand_bytes(32),
          last_public_key: :crypto.strong_rand_bytes(32)
        }
      ]

      Enum.each(seeds, &NetworkLedger.add_node_info/1)

      Bootstrap.run({127, 0, 0, 1}, 3000, DateTime.utc_now(), seeds)

      assert_received :node_ready
    end

    test "update node" do
      MockStorage
      |> stub(:write_transaction_chain, fn [
                                             %Transaction{
                                               type: :node
                                             }
                                           ] ->
        :ok
      end)

      {:ok, counter} = Agent.start_link(fn -> 0 end)

      MockCrypto
      |> stub(:increment_number_of_generate_node_keys, fn ->
        Agent.update(counter, &(&1 + 1))
      end)
      |> stub(:number_of_node_keys, fn ->
        Agent.get(counter, & &1)
      end)

      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: :crypto.strong_rand_bytes(32),
          last_public_key: :crypto.strong_rand_bytes(32)
        }
      ]

      Enum.each(seeds, &NetworkLedger.add_node_info/1)

      Bootstrap.run({127, 0, 0, 1}, 3000, DateTime.utc_now(), seeds)

      assert_received :node_ready

      {:ok,
       %Node{
         ip: {127, 0, 0, 1},
         first_public_key: first_public_key,
         last_public_key: last_public_key
       }} = P2P.node_info()

      assert first_public_key == Crypto.node_public_key(0)
      assert last_public_key == Crypto.node_public_key(0)

      Bootstrap.run({200, 50, 20, 10}, 3000, DateTime.utc_now(), seeds)

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
