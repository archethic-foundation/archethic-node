defmodule Archethic.Utils.Regression.Playbook.UCO do
  @moduledoc """
  Play and verify UCO ledger.
  """

  require Logger

  alias Archethic.Crypto

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  alias Archethic.Utils.Regression.Api
  alias Archethic.Utils.WebSocket.Client, as: WSClient
  @unit_uco 100_000_000

  use Archethic.Utils.Regression.Playbook

  def play!(nodes, opts) do
    Logger.info("Play UCO transactions on #{inspect(nodes)} with #{inspect(opts)}")
    port = Application.get_env(:archethic, ArchethicWeb.Endpoint)[:http][:port]
    host = :lists.nth(:rand.uniform(length(nodes)), nodes)

    endpoint = %Api{host: host, port: port, protocol: :http}
    WSClient.start_link(host: host, port: port)

    run_transfers(endpoint)
  end

  defp run_transfers(endpoint) do
    invalid_transfer(endpoint)

    single_recipient_transfer(endpoint)
  end

  defp single_recipient_transfer(endpoint) do
    recipient_seed = "recipient_1"

    recipient_address =
      Crypto.derive_keypair(recipient_seed, 0)
      |> elem(0)
      |> Crypto.derive_address()

    prev_balance = Api.get_uco_balance(recipient_address, endpoint)
    Api.send_funds_to_seeds(%{recipient_seed => 10}, endpoint)
    new_balance = Api.get_uco_balance(recipient_address, endpoint)

    true =
      new_balance -
        prev_balance == trunc(@unit_uco * 10)

    Logger.info("#{Base.encode16(recipient_address)} received 10 UCO")

    new_recipient_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    Logger.info(
      "#{Base.encode16(recipient_address)} is sending 5 UCO to #{Base.encode16(new_recipient_address)}"
    )

    {:ok, address} =
      Api.send_transaction_with_await_replication(
        recipient_seed,
        :transfer,
        %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %UCOTransfer{
                  to: new_recipient_address,
                  amount: trunc(5 * @unit_uco)
                }
              ]
            }
          }
        },
        endpoint
      )

    Logger.info("Transaction #{Base.encode16(address)} submitted")

    # Ensure the second recipient received the 5.0 UCO
    true = 5 * @unit_uco == Api.get_uco_balance(new_recipient_address, endpoint)
    Logger.info("#{Base.encode16(new_recipient_address)} received 5.0 UCO")

    # Ensure the first recipient amount have decreased
    recipient_balance2 = Api.get_uco_balance(recipient_address, endpoint)
    # 5.0 - transaction fee
    true = recipient_balance2 <= new_balance - 5 * @unit_uco
    Logger.info("#{Base.encode16(recipient_address)} now got #{recipient_balance2} UCO")
  end

  defp invalid_transfer(endpoint) do
    from_seed = :crypto.strong_rand_bytes(32)
    recipient_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    {:ok, _tx_address} =
      Api.send_transaction(
        from_seed,
        :transfer,
        %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %UCOTransfer{
                  to: recipient_address,
                  amount: 10 * @unit_uco
                }
              ]
            }
          }
        },
        endpoint
      )

    Process.sleep(1000)

    0 = Api.get_uco_balance(recipient_address, endpoint)
    0 = Api.get_chain_size(from_seed, Crypto.default_curve(), endpoint)

    Logger.info("Transaction with insufficient funds is rejected")
  end
end
