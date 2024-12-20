defmodule ArchethicWeb.Explorer.FaucetControllerTest do
  use ArchethicCase, async: false
  use ArchethicWeb.ConnCase

  alias Archethic.{Crypto, P2P, P2P.Node, PubSub, P2P.Message, TransactionChain}
  alias Archethic.{BeaconChain.ReplicationAttestation, TransactionChain.TransactionData}

  alias Message.{GetLastTransactionAddress, GetTransactionChainLength, LastTransactionAddress, Ok}
  alias Message.{StartMining, TransactionChainLength, GetGenesisAddress, GenesisAddress}

  alias TransactionData.{Ledger, UCOLedger}
  alias TransactionChain.{Transaction, TransactionSummary}

  alias ArchethicWeb.Explorer.FaucetRateLimiter

  import ArchethicCase, only: [setup_before_send_tx: 0]
  import Mox

  @pool_seed Application.compile_env(:archethic, [ArchethicWeb.Explorer.FaucetController, :seed])

  setup do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    setup_before_send_tx()
    start_supervised(FaucetRateLimiter)
    :ok
  end

  describe "create_transfer/2" do
    test "should show success flash with tx URL on valid transaction", %{conn: conn} do
      recipient_address =
        Crypto.generate_deterministic_keypair("seed")
        |> elem(0)
        |> Crypto.derive_address()
        |> Base.encode16()

      FaucetRateLimiter.clean_address(recipient_address)

      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %UCOLedger.Transfer{
                    to: recipient_address,
                    amount: 10_000_000_000
                  }
                ]
              }
            }
          },
          @pool_seed,
          0,
          curve: Crypto.default_curve()
        )

      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: "1234"}}

        _, %GetTransactionChainLength{}, _ ->
          {:ok, %TransactionChainLength{length: 0}}

        _, %StartMining{}, _ ->
          PubSub.notify_new_transaction(tx.address)

          PubSub.notify_replication_attestation(%ReplicationAttestation{
            transaction_summary: %TransactionSummary{
              address: tx.address
            }
          })

          {:ok, %Ok{}}

        _, %GetGenesisAddress{}, _ ->
          {:ok, %GenesisAddress{address: tx.address, timestamp: DateTime.utc_now()}}
      end)

      conn = post(conn, Routes.faucet_path(conn, :create_transfer), address: recipient_address)

      assert html_response(conn, 200) =~
               Base.encode16(tx.address)
    end

    test "should show 'Malformed address' flash on invalid address", %{conn: conn} do
      conn = post(conn, Routes.faucet_path(conn, :create_transfer), address: "XYZ")

      assert html_response(conn, 200) =~
               "Malformed address"
    end

    test "should show error flash on faucet rate limit is reached", %{conn: conn} do
      faucet_rate_limit = Application.get_env(:archethic, :faucet_rate_limit)

      recipient_address = "000098fe10e8633bce19c59a40a089731c1f72b097c5a8f7dc71a37eb26913aa4f80"

      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %UCOLedger.Transfer{
                    to: recipient_address,
                    amount: 10_000_000_000
                  }
                ]
              }
            }
          },
          @pool_seed,
          0,
          curve: Crypto.default_curve()
        )

      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: "1234"}}

        _, %GetTransactionChainLength{}, _ ->
          {:ok, %TransactionChainLength{length: 0}}

        _, %StartMining{}, _ ->
          PubSub.notify_new_transaction(tx.address)

          PubSub.notify_replication_attestation(%ReplicationAttestation{
            transaction_summary: %TransactionSummary{
              address: tx.address
            }
          })

          {:ok, %Ok{}}

        _, %GetGenesisAddress{}, _ ->
          {:ok, %GenesisAddress{address: tx.address, timestamp: DateTime.utc_now()}}

        _, %Archethic.P2P.Message.ListNodes{}, _ ->
          {:ok, %Archethic.P2P.Message.NodeList{nodes: Archethic.P2P.list_nodes()}}
      end)

      faucet_requests =
        for _request_index <- 1..(faucet_rate_limit + 1) do
          post(conn, Routes.faucet_path(conn, :create_transfer), address: recipient_address)
        end

      faucet_requests
      |> Enum.with_index()
      |> Enum.each(fn {conn, index} ->
        if index == faucet_rate_limit,
          do: assert(html_response(conn, 200) =~ "Blocked address"),
          else: assert(html_response(conn, 200) =~ Base.encode16(tx.address))
      end)
    end
  end
end
