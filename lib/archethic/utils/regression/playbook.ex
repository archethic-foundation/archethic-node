defmodule ArchEthic.Utils.Regression.Playbook do
  @moduledoc """
  Playbook is executed on a testnet to verify correctness of the testnet.
  """
  require Logger
  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger.Transfer, as: NFTTransfer
  alias ArchEthic.TransactionChain.TransactionData.Ownership
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  alias ArchEthic.Utils.WebClient

  @callback play!([String.t()], Keyword.t()) :: :ok

  @genesis_origin_private_key "01009280BDB84B8F8AEDBA205FE3552689964A5626EE2C60AA10E3BF22A91A036009"
                              |> Base.decode16!()

  @faucet_seed Application.compile_env(:archethic, [ArchEthicWeb.FaucetController, :seed])

  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour ArchEthic.Utils.Regression.Playbook
    end
  end

  def send_funds_to(recipient_address, host, port, amount \\ 10) do
    send_transaction(
      @faucet_seed,
      :transfer,
      %TransactionData{
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers: [
              %UCOTransfer{
                to: recipient_address,
                amount: amount * 100_000_000
              }
            ]
          }
        }
      },
      host,
      port,
      :ed25519
    )
  end

  def send_transaction(
        transaction_seed,
        tx_type,
        transaction_data = %TransactionData{},
        host,
        port,
        curve \\ Crypto.default_curve()
      ) do
    alias ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper

    chain_length = get_chain_size(transaction_seed, curve, host, port)

    {previous_public_key, previous_private_key} =
      Crypto.derive_keypair(transaction_seed, chain_length, curve)

    {next_public_key, _} = Crypto.derive_keypair(transaction_seed, chain_length + 1, curve)

    IO.inspect(Base.encode16(Crypto.derive_address(next_public_key)), label: "txn======>address")

    Process.sleep(15_000)

    replication_subscription =
      TPSHelper.await_replication(Crypto.derive_address(next_public_key), host, port)

    tx =
      %Transaction{
        address: Crypto.derive_address(next_public_key),
        type: tx_type,
        data: transaction_data,
        previous_public_key: previous_public_key
      }
      |> Transaction.previous_sign_transaction(previous_private_key)
      |> Transaction.origin_sign_transaction(@genesis_origin_private_key)

    true =
      Crypto.verify?(
        tx.previous_signature,
        Transaction.extract_for_previous_signature(tx) |> Transaction.serialize(),
        tx.previous_public_key
      )

<<<<<<< HEAD
    IO.inspect("txn sent data")
=======
      replication_subscription = ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper.await_replication(tx.address, host, port)
>>>>>>> temp

    case WebClient.with_connection(
           host,
           port,
           &WebClient.json(&1, "/api/transaction", tx_to_json(tx))
         ) do
      {:ok, %{"status" => "pending"}} ->
        data = Task.await(replication_subscription)
        data |> IO.inspect(label: "replication output")
        {:ok, tx.address}

        data = Task.await(replication_subscription)
        Logger.debug("case dispatch", binding())

      _ ->
        :error
    end
  end

  defp tx_to_json(%Transaction{
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
              Enum.map(uco_transfers, fn %UCOTransfer{to: to, amount: amount} ->
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

  def get_chain_size(seed, curve, host, port) do
    genesis_address =
      seed
      |> Crypto.derive_keypair(0, curve)
      |> elem(0)
      |> Crypto.derive_address()

    query =
      ~s|query {last_transaction(address: "#{Base.encode16(genesis_address)}"){ chainLength }}|

    case WebClient.with_connection(host, port, &WebClient.query(&1, query)) do
      {:ok, %{"errors" => [%{"message" => "transaction_not_exists"}]}} ->
        0

      {:ok, %{"data" => %{"last_transaction" => %{"chainLength" => chain_length}}}} ->
        chain_length

    end
  end

  def get_uco_balance(address, host, port) do
    query = ~s|query {lastTransaction(address: "#{Base.encode16(address)}"){ balance { uco }}}|

    case WebClient.with_connection(host, port, &WebClient.query(&1, query)) do
      {:ok, %{"data" => %{"lastTransaction" => %{"balance" => %{"uco" => uco}}}}} ->
        uco

      {:ok, %{"errors" => [%{"message" => "transaction_not_exists"}]}} ->
        balance_query = ~s| query { balance(address: "#{Base.encode16(address)}") { uco } } |

        {:ok,
         %{
           "data" => %{
             "balance" => %{
               "uco" => uco
             }
           }
         }} = WebClient.with_connection(host, port, &WebClient.query(&1, balance_query))

        uco
    end
  end

  def storage_nonce_public_key(host, port) do
    query = ~s|query {sharedSecrets { storageNoncePublicKey}}|

    case WebClient.with_connection(host, port, &WebClient.query(&1, query)) do
      {:ok,
       %{
         "data" => %{
           "sharedSecrets" => %{"storageNoncePublicKey" => storage_nonce_public_key}
         }
       }} ->
        Base.decode16!(storage_nonce_public_key)
    end
  end
end
