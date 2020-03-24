defmodule UnirisSync.BootstrapTest do
  use ExUnit.Case

  import Mox

  alias UnirisP2P, as: P2P
  alias UnirisP2P.Node
  alias UnirisSync.Bootstrap
  alias UnirisCrypto, as: Crypto
  alias UnirisChain.Transaction

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    me = self()

    MockP2P
    |> stub(:list_seeds, fn ->
      [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key: "00CD747D4CB84C07B1E26F241EA1105579CBF94F543658995C9E694B55F919E120",
          first_public_key: "00CD747D4CB84C07B1E26F241EA1105579CBF94F543658995C9E694B55F919E120"
        }
      ]
    end)
    |> stub(:update_seeds, fn _ ->
      send(me, :updated_seeds)
      :ok
    end)
    |> stub(:send_message, fn _, msg ->
      case msg do
        [:new_seeds, {:closest_nodes, _}, {:bootstrap_crypto_seeds, pub}] ->
          [
            [
              %Node{
                ip: {200, 40, 30, 50},
                port: 3000,
                last_public_key:
                  "00B062E1F7C6362C6F621ED93420122AA5AB21C8653FF04C73EB6F77CC68AEAF73",
                first_public_key:
                  "00B062E1F7C6362C6F621ED93420122AA5AB21C8653FF04C73EB6F77CC68AEAF73"
              }
            ],
            [
              %Node{
                ip: {80, 10, 252, 47},
                port: 3000,
                last_public_key:
                  "0059372A63A9A4BE6D00F3673F5D497B5D10A93C69125DAEF309E85E40D74CA0BF",
                first_public_key:
                  "0059372A63A9A4BE6D00F3673F5D497B5D10A93C69125DAEF309E85E40D74CA0BF"
              }
            ],
            %{
              origin_keys_seeds: Crypto.ec_encrypt(["origin_seed"], pub),
              storage_nonce_seed: Crypto.ec_encrypt("storage_nonce_seed", pub)
            }
          ]

        {:new_transaction, %Transaction{type: :node}} ->
          send(me, {:acknowledge_storage, ""})
          :ok

        {:new_transaction, %Transaction{type: :node_shared_secrets}} ->
          send(me, {:acknowledge_storage, ""})
          :ok
      end
    end)
    |> stub(:add_node, fn _ ->
      :ok
    end)
    |> stub(:connect_node, fn _ ->
      :ok
    end)
    |> stub(:node_info, fn _ ->
      {:ok,
       %Node{
         ip: {127, 0, 0, 1},
         port: 3000,
         first_public_key: "",
         last_public_key: ""
       }}
    end)

    MockSharedSecrets
    |> stub(:new_shared_secrets_transaction, fn seed ->
      aes_key = :crypto.strong_rand_bytes(32)

      Transaction.from_seed(seed, :node_shared_secrets, %Transaction.Data{
        keys: %{
          secret:
            Crypto.aes_encrypt(
              %{
                daily_nonce_seed: :crypto.strong_rand_bytes(32),
                storage_nonce_seed: :crypto.strong_rand_bytes(32),
                origin_keys_seeds: [:crypto.strong_rand_bytes(32)]
              },
              aes_key
            ),
          authorized_keys:
            %{}
            |> Map.put(
              Crypto.node_public_key(),
              Crypto.ec_encrypt(aes_key, Crypto.node_public_key())
            )
        }
      })
    end)
    |> stub(:add_origin_public_key, fn _, _ -> :ok end)

    :ok
  end

  test "create_local_node/4 should create a new node process for the local node" do
    assert %Node{} =
             Bootstrap.create_local_node("127.0.0.1", 3000, "first_public_key", "last_public_key")
  end

  test "create_node_transaction/4 should create a new transaction" do
    Crypto.add_origin_seed("origin_seed")

    tx =
      Bootstrap.create_node_transaction(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key:
          <<0, 195, 217, 87, 74, 44, 143, 133, 202, 49, 24, 21, 172, 125, 120, 229, 214, 229, 203,
            0, 171, 137, 3, 53, 26, 206, 212, 108, 55, 78, 175, 52, 104>>,
        last_public_key:
          <<0, 195, 217, 87, 74, 44, 143, 133, 202, 49, 24, 21, 172, 125, 120, 229, 214, 229, 203,
            0, 171, 137, 3, 53, 26, 206, 212, 108, 55, 78, 175, 52, 104>>
      })

    assert %Transaction{
             data: %{
               content: """
                 ip: 127.0.0.1
                 port: 3000
                 first_public_key: 00C3D9574A2C8F85CA311815AC7D78E5D6E5CB00AB8903351ACED46C374EAF3468
                 last_public_key: 00C3D9574A2C8F85CA311815AC7D78E5D6E5CB00AB8903351ACED46C374EAF3468
               """
             }
           } = tx
  end

  test "request_init_data/ should return a list of new seeds, closest nodes and bootstraping seed decrypted" do
    previous_seeds = P2P.list_seeds()

    {new_seeds, closest_nodes, origin_seeds, storage_nonce_seed} =
      Bootstrap.request_init_data(previous_seeds, "AAA")

    assert Enum.map(new_seeds, & &1.last_public_key) == [
             "00B062E1F7C6362C6F621ED93420122AA5AB21C8653FF04C73EB6F77CC68AEAF73"
           ]

    assert Enum.map(closest_nodes, & &1.last_public_key) == [
             "0059372A63A9A4BE6D00F3673F5D497B5D10A93C69125DAEF309E85E40D74CA0BF"
           ]

    assert origin_seeds == ["origin_seed"]
    assert storage_nonce_seed == "storage_nonce_seed"
  end

  test "initialize_node/2 initialize a node by retrieving initializing data, update the new sees and setup the chain" do
    previous_seeds = P2P.list_seeds()

    MockP2P
    |> stub(:list_nodes, fn ->
      {pub, _} = Crypto.generate_deterministic_keypair("otherseed")

      [
        %Node{
          ip: {80, 20, 30, 50},
          port: 3000,
          first_public_key: pub,
          last_public_key: pub
        }
      ]
    end)

    Bootstrap.initialize_node(
      %Node{
        ip: {127, 0, 0, 1},
        port: 5000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        geo_patch: "AAA"
      },
      previous_seeds
    )

    assert P2P.list_seeds() |> Enum.map(& &1.first_public_key) == [
             "00CD747D4CB84C07B1E26F241EA1105579CBF94F543658995C9E694B55F919E120"
           ]
  end
end
