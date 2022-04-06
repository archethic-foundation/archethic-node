defmodule ArchEthicWeb.FaucetControllerTest do
  use ArchEthicCase
  use ArchEthicWeb.ConnCase

  alias ArchEthic.{
    Crypto,
    P2P,
    P2P.Node,
    PubSub
  }

  alias ArchEthic.P2P.Message.{
    GetLastTransactionAddress,
    GetTransactionChainLength,
    LastTransactionAddress,
    Ok,
    StartMining,
    TransactionChainLength
  }

  alias ArchEthic.TransactionChain.{
    Transaction,
    TransactionData,
    TransactionData.Ledger,
    TransactionData.UCOLedger
  }

  alias ArchEthicWeb.FaucetRateLimiter

  import Mox

  @pool_seed Application.compile_env(:archethic, [ArchEthicWeb.FaucetController, :seed])

  setup do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    :ok
  end

  describe "create_transfer/2" do
    test "should show success flash with tx URL on valid transaction", %{conn: conn} do
      recipient_address = "000098fe10e8633bce19c59a40a089731c1f72b097c5a8f7dc71a37eb26913aa4f80"
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
          Crypto.default_curve()
        )

      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: "1234"}}

        _, %GetTransactionChainLength{}, _ ->
          {:ok, %TransactionChainLength{length: 0}}

        _, %StartMining{}, _ ->
          PubSub.notify_new_transaction(tx.address)

          {:ok, %Ok{}}
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
          Crypto.default_curve()
        )

      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: "1234"}}

        _, %GetTransactionChainLength{}, _ ->
          {:ok, %TransactionChainLength{length: 0}}

        _, %StartMining{}, _ ->
          PubSub.notify_new_transaction(tx.address)

          {:ok, %Ok{}}
      end)

      faucet_requests =
        for _request_index <- 1..(faucet_rate_limit + 1) do
          post(conn, Routes.faucet_path(conn, :create_transfer), address: recipient_address)
        end

      conn = List.last(faucet_requests)

      assert html_response(conn, 200) =~ "Blocked address"
    end
  end
end
