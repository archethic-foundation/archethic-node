defmodule ArchEthic.Utils.Regression.Playbook.UCO do
  @moduledoc """
  Play and verify UCO ledger.
  """

  require Logger

  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  alias ArchEthic.Utils.Regression.Playbook

  use Playbook

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
    recipient_address =
      Crypto.derive_keypair("recipient_1", 0) |> elem(0) |> Crypto.derive_address()

    Logger.info(
      "Genesis pool allocation owner is sending 10 UCO to #{Base.encode16(recipient_address)}"
    )

    prev_balance = Playbook.get_uco_balance(recipient_address, host, port)

    {:ok, address} = Playbook.send_funds_to(recipient_address, host, port)

    Logger.info("Transaction #{Base.encode16(address)} submitted")

    Process.sleep(1_000)

    # Ensure the recipient got the 10.0 UCO
    new_balance = Playbook.get_uco_balance(recipient_address, host, port)

    true =
      ((new_balance * 100_000_000) |> Float.round() |> trunc()) -
        ((prev_balance * 100_000_000) |> Float.round() |> trunc()) == 100_000_000 * 10

    Logger.info("#{Base.encode16(recipient_address)} received 10 UCO")

    new_recipient_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    Logger.info(
      "#{Base.encode16(recipient_address)} is sending 5 UCO to #{Base.encode16(new_recipient_address)}"
    )

    {:ok, address} =
      Playbook.send_transaction(
        "recipient_1",
        :transfer,
        %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %UCOTransfer{
                  to: new_recipient_address,
                  amount: 5 * 100_000_000
                }
              ]
            }
          }
        },
        host,
        port
      )

    Logger.info("Transaction #{Base.encode16(address)} submitted")

    Process.sleep(1_000)

    # Ensure the second recipient received the 5.0 UCO
    5.0 = Playbook.get_uco_balance(new_recipient_address, host, port)
    Logger.info("#{Base.encode16(new_recipient_address)} received 5.0 UCO")

    # Ensure the first recipient amount have decreased
    recipient_balance2 = Playbook.get_uco_balance(recipient_address, host, port)
    # 5.0 - transaction fee
    true = recipient_balance2 <= new_balance - 5.0
    Logger.info("#{Base.encode16(recipient_address)} now got #{recipient_balance2} UCO")
  end

  defp invalid_transfer(host, port) do
    from_seed = :crypto.strong_rand_bytes(32)
    recipient_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    {:ok, _tx_address} =
      Playbook.send_transaction(
        from_seed,
        :transfer,
        %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %UCOTransfer{
                  to: recipient_address,
                  amount: 10 * 100_000_000
                }
              ]
            }
          }
        },
        host,
        port
      )

    Process.sleep(1_000)
    0.0 = Playbook.get_uco_balance(recipient_address, host, port)
    0 = Playbook.get_chain_size(from_seed, Crypto.default_curve(), host, port)

    Logger.info("Transaction with insufficient funds is rejected")
  end
end
