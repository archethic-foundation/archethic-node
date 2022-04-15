defmodule ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper do
  @moduledoc """
    Helper Method for Exposed api Benchmaking
  """

  # module alias
  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger.Transfer, as: NFTTransfer
  alias ArchEthic.TransactionChain.TransactionData.Ownership
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer

  #  alias ArchEthicWeb.TransactionSubscriber

  alias ArchEthic.Utils.WebClient

  #  module constants
  @pool_seed Application.compile_env(:archethic, [ArchEthicWeb.FaucetController, :seed])

  @genesis_origin_private_key "01009280BDB84B8F8AEDBA205FE3552689964A5626EE2C60AA10E3BF22A91A036009"
                              |> Base.decode16!()

  def get_curve(), do: Crypto.default_curve()

  def random_seed(), do: Integer.to_string(System.unique_integer([:monotonic]))

  def derive_keypair(seed, index \\ 0), do: Crypto.derive_keypair(seed, index, get_curve())

  def acquire_genesis_address({pbKey, _privKey}), do: Crypto.derive_address(pbKey)

  def get_address(pbKey), do: Crypto.derive_address(pbKey)

  @spec faucet_enabled?() :: {:ok, boolean()}
  def faucet_enabled?(),
    do: {
      :ok,
      # System.get_env("ARCHETHIC_NETWORK_TYPE") == "testnet"}
      true
    }

  def allocate_funds(recipient_address, host, port) do
    with {:ok, true} <- faucet_enabled?(),
         #  {:ok, recipient_address} <- Base.decode16(recipient_address, case: :mixed),
         true <- Crypto.valid_address?(recipient_address) do
      txn =
        @pool_seed
        |> build_txn(recipient_address, :transfer, host, port, 10_000_000_000)

      IO.inspect(Base.encode16(txn.address), label: "======tx addressin allocate funds====")
      Process.sleep(10_000)

      deploy_txn(txn, host, port)
    else
      _ -> raise "Allocate Funds: formalities failed"
    end
  end

  def get_transaction_data(recipient_address, amount),
    do: %TransactionData{
      ledger: %Ledger{
        uco: %UCOLedger{
          transfers: [
            %Transfer{
              to: recipient_address,
              amount: amount
            }
          ]
        }
      }
    }

  def get_chain_size(seed, host, port) do
    genesis_address = seed |> derive_keypair() |> acquire_genesis_address()

    query =
      ~s|query {last_transaction(address: "#{Base.encode16(genesis_address)}"){ chainLength }}|

    IO.inspect("def get_chain_size(", label: "get chain size")

    case WebClient.with_connection("#{host}", port, &WebClient.query(&1, query), :http,
           timeout: 5_000
         ) do
      {:ok, %{"errors" => [%{"message" => "transaction_not_exists"}]}} ->
        0

      {:ok, %{"data" => %{"last_transaction" => %{"chainLength" => chain_length}}}} ->
        chain_length

      {:error, a} ->
        raise "chain size failed #{a}"
    end
  end

  def build_txn(emitter_seed, recipient_address, txn_type, host, port, amount \\ 1_000_000) do
    txn_data = get_transaction_data(recipient_address, amount)

    chain_length = get_chain_size(emitter_seed, host, port)

    {prev_pbKey, prev_privKey} = derive_keypair(emitter_seed, chain_length)

    {next_pbKey, _next_privKey} = derive_keypair(emitter_seed, chain_length + 1)
    IO.inspect("def build_txn(emitter_seed,", label: "build_txn")

    %Transaction{
      address: get_address(next_pbKey),
      type: txn_type,
      data: txn_data,
      previous_public_key: prev_pbKey
    }
    |> Transaction.previous_sign_transaction(prev_privKey)
    |> Transaction.origin_sign_transaction(@genesis_origin_private_key)
  end

  def deploy_txn(txn, host, port) do
    subscribe_to_replication =
      Task.async(fn -> register_for_replication_attestation(txn.address, host, port) end)

    case dispatch_txn_to_public_endpoint(txn, host, port) do
      {:ok, _txn_address} ->
        Task.await(subscribe_to_replication)
        |> IO.inspect(label: "replication output")

      {:error, nil} ->
        raise "Sending txn failed"
    end
  end

  def dispatch_txn_to_public_endpoint(txn, host, port) do
    true =
      Crypto.verify?(
        txn.previous_signature,
        Transaction.extract_for_previous_signature(txn) |> Transaction.serialize(),
        txn.previous_public_key
      )

    case WebClient.with_connection(
           host,
           port,
           &WebClient.json(&1, "/api/transaction", txn_to_json(txn))
         ) do
      {:ok, %{"status" => "pending"}} ->
        {:ok, txn.address}

      _ ->
        {:error, nil}
    end
  end

  def register_for_replication_attestation(txn_address, _host, _port) do
    IO.inspect("inside replication")

    _query =
      "subscription { transactionConfirmed(address: \"#{Base.encode16(txn_address)}\") { address, nbConfirmations } }"
      txn_address  = "0000c084b09c60e3bde2d0a81df08b20d82d8b6dfc1d39bc3dfa5e41b731718f09e1"
      query =
           "subscription { transactionConfirmed(address: \"#{Base.encode16(txn_address)}\") { address, nbConfirmations } }"

     {:ok, conn} = Mint.HTTP.connect(:http, "localhost", 4_000)
       #  |>IO.inspect(label: "1")
     {:ok, conn, ref} = Mint.WebSocket.upgrade(:ws, conn, "/socket/websocket?vsn=2.0.0", [
       Mint.WebSocket.PerMessageDeflate
     ])
     |>IO.inspect(label: "2")


     http_reply_message = receive(do: (message -> message))
     |>IO.inspect(label: "3")

  end

  # {:ok}
  #   %{
  #   result: %{
  #     data: %{
  #       "transactionConfirmed" => %{"address" => recv_addr, "nbConfirmations" => 1}
  #     }
  #   },
  #   subscriptionId: ^subscription_id
  # }

  defp txn_to_json(%Transaction{
         version: version,
         address: address,
         type: type,
         data: %TransactionData{
           ledger: %Ledger{
             uco: %UCOLedger{transfers: uco_transfers},
             nft: %NFTLedger{transfers: nft_transfers}
           },
           code: code,
           content: content,
           recipients: recipients,
           ownerships: ownerships
         },
         previous_public_key: previous_public_key,
         previous_signature: previous_signature,
         origin_signature: origin_signature
       }) do
    %{
      "version" => version,
      "address" => Base.encode16(address),
      "type" => Atom.to_string(type),
      "previousPublicKey" => Base.encode16(previous_public_key),
      "previousSignature" => Base.encode16(previous_signature),
      "originSignature" => Base.encode16(origin_signature),
      "data" => %{
        "ledger" => %{
          "uco" => %{
            "transfers" =>
              Enum.map(uco_transfers, fn %Transfer{to: to, amount: amount} ->
                %{"to" => Base.encode16(to), "amount" => amount}
              end)
          },
          "nft" => %{
            "transfers" =>
              Enum.map(nft_transfers, fn %NFTTransfer{
                                           to: to,
                                           amount: amount,
                                           nft: nft_address
                                         } ->
                %{"to" => Base.encode16(to), "amount" => amount, "nft" => nft_address}
              end)
          }
        },
        "code" => code,
        "content" => content,
        "recipients" => Enum.map(recipients, &Base.encode16(&1)),
        "ownerships" =>
          Enum.map(ownerships, fn %Ownership{
                                    secret: secret,
                                    authorized_keys: authorized_keys
                                  } ->
            %{
              "secret" => Base.encode16(secret),
              "authorizedKeys" =>
                Enum.map(authorized_keys, fn {public_key, encrypted_secret_key} ->
                  %{
                    "publicKey" => Base.encode16(public_key),
                    "encryptedSecretKey" => Base.encode16(encrypted_secret_key)
                  }
                end)
            }
          end)
      }
    }
  end
end
