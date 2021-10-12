defmodule ArchEthic.Utils.Regression.Playbook.UCO do
  @moduledoc """
  Play and verify UCO ledger.

  TODO
  """

  require Logger

  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  alias ArchEthic.Utils.Regression.Playbook
  alias ArchEthic.Utils.WebClient

  @behaviour Playbook

  @genesis_origin_private_key "01009280BDB84B8F8AEDBA205FE3552689964A5626EE2C60AA10E3BF22A91A036009"
                              |> Base.decode16!()

  @faucet_seed Application.compile_env(:archethic, [ArchEthicWeb.FaucetController, :seed])

  def play!(nodes, opts) do
    Logger.info("Play UCO transactions on #{inspect(nodes)} with #{inspect(opts)}")
    port = Application.get_env(:archethic, ArchEthicWeb.Endpoint)[:http][:port]
    host = :lists.nth(:rand.uniform(length(nodes)), nodes)

    run_transfers(host, port)
  end

  defp run_transfers(host, port) do
    invalid_transfer(host, port)

    single_recipient_transfer(host, port)
  end

  defp single_recipient_transfer(host, port) do
    recipient_address = Crypto.derive_keypair("recipient_1", 0) |> elem(0) |> Crypto.hash()

    Logger.info(
      "Genesis pool allocation owner is sending 10 UCO to #{Base.encode16(recipient_address)}"
    )

    prev_balance = get_uco_balance(recipient_address, host, port)

    {:ok, address} =
      send_transfer_transaction(
        @faucet_seed,
        [%{to: recipient_address, amount: 10 * 100_000_000}],
        host,
        port,
        :ed25519
      )

    Logger.info("Transaction #{Base.encode16(address)} submitted")

    # Ensure the recipient got the 10.0 UCO
    new_balance = get_uco_balance(recipient_address, host, port)
    true = new_balance == prev_balance + 10.0

    Logger.info("#{Base.encode16(recipient_address)} received 10 UCO")

    new_recipient_address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    Logger.info(
      "#{Base.encode16(recipient_address)} is sending 5 UCO to #{Base.encode16(new_recipient_address)}"
    )

    {:ok, address} =
      send_transfer_transaction(
        "recipient_1",
        [%{to: new_recipient_address, amount: 5 * 100_000_000}],
        host,
        port,
        :ed25519
      )

    Logger.info("Transaction #{Base.encode16(address)} submitted")

    # Ensure the second recipient received the 5.0 UCO
    5.0 = get_uco_balance(new_recipient_address, host, port)
    Logger.info("#{Base.encode16(new_recipient_address)} received 5.0 UCO")

    # Ensure the first recipient amount have decreased
    recipient_balance2 = get_uco_balance(recipient_address, host, port)
    # 5.0 - transaction fee
    true = recipient_balance2 <= new_balance - 5.0
    Logger.info("#{Base.encode16(recipient_address)} now got #{recipient_balance2} UCO")
  end

  defp invalid_transfer(host, port) do
    from_seed = :crypto.strong_rand_bytes(32)
    recipient_address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

    :error =
      send_transfer_transaction(
        from_seed,
        [%{to: recipient_address, amount: 10 * 100_000_000}],
        host,
        port,
        :secp256r1
      )

    Logger.info("Transaction with insufficient funds is rejected")
  end

  defp send_transfer_transaction(transaction_seed, transfers, host, port, curve) do
    chain_length = get_chain_size(transaction_seed, curve, host, port)

    {previous_public_key, previous_private_key} =
      Crypto.derive_keypair(transaction_seed, chain_length, curve)

    {next_public_key, _} = Crypto.derive_keypair(transaction_seed, chain_length + 1, curve)

    tx =
      %Transaction{
        address: Crypto.hash(next_public_key),
        type: :transfer,
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers:
                Enum.map(transfers, fn %{to: to, amount: amount} ->
                  %UCOTransfer{to: to, amount: amount}
                end)
            }
          }
        },
        previous_public_key: previous_public_key
      }
      |> Transaction.previous_sign_transaction(previous_private_key)
      |> Transaction.origin_sign_transaction(@genesis_origin_private_key)

    tx_json = %{
      "version" => tx.version,
      "address" => Base.encode16(tx.address),
      "type" => "transfer",
      "previousPublicKey" => Base.encode16(tx.previous_public_key),
      "previousSignature" => Base.encode16(tx.previous_signature),
      "originSignature" => Base.encode16(tx.origin_signature),
      "data" => %{
        "ledger" => %{
          "uco" => %{
            "transfers" =>
              Enum.map(transfers, fn %{to: to, amount: amount} ->
                %{"to" => Base.encode16(to), "amount" => amount}
              end)
          }
        }
      }
    }

    case WebClient.with_connection(host, port, &WebClient.json(&1, "/api/transaction", tx_json)) do
      {:ok, %{"status" => "ok"}} ->
        {:ok, tx.address}

      _ ->
        :error
    end
  end

  defp get_chain_size(seed, curve, host, port) do
    genesis_address =
      seed
      |> Crypto.derive_keypair(0, curve)
      |> elem(0)
      |> Crypto.hash()

    query =
      ~s|query {last_transaction(address: "#{Base.encode16(genesis_address)}"){ chainLength }}|

    case WebClient.with_connection(host, port, &WebClient.query(&1, query)) do
      {:ok, %{"errors" => [%{"message" => "transaction_not_exists"}]}} ->
        0

      {:ok, %{"data" => %{"last_transaction" => %{"chainLength" => chain_length}}}} ->
        chain_length
    end
  end

  defp get_uco_balance(address, host, port) do
    query = ~s|query {lastTransaction(address: "#{Base.encode16(address)}"){ balance { uco }}}|

    case WebClient.with_connection(host, port, &WebClient.query(&1, query |> IO.inspect())) do
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
end
