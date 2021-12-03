defmodule ArchEthic.Utils.Regression.Playbook.SmartContract do
  @moduledoc """
  Play and verify smart contracts.
  """

  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ownership

  alias ArchEthic.Utils.Regression.Playbook

  require Logger

  use Playbook

  def play!(nodes, opts) do
    Crypto.Ed25519.LibSodiumPort.start_link()

    Logger.info("Play smart contract transactions on #{inspect(nodes)} with #{inspect(opts)}")
    port = Application.get_env(:archethic, ArchEthicWeb.Endpoint)[:http][:port]
    host = :lists.nth(:rand.uniform(length(nodes)), nodes)

    run_smart_contracts(host, port)
  end

  defp run_smart_contracts(host, port) do
    storage_node_public_key = Playbook.storage_nonce_public_key(host, port)

    run_interval_date_trigger(host, port, storage_node_public_key)
  end

  defp run_interval_date_trigger(host, port, storage_node_public_key) do
    recipient_address2 = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    amount_to_send = trunc(0.1 * 100_000_000)

    contract_owner_address =
      Crypto.derive_keypair("contract_playbook_seed", 0, :ed25519)
      |> elem(0)
      |> Crypto.hash()

    Logger.info(
      "Genesis pool allocation owner is sending 10 UCO to #{Base.encode16(contract_owner_address)}"
    )

    {:ok, _funding_tx_address} = Playbook.send_funds_to(contract_owner_address, host, port)

    secret_key = :crypto.strong_rand_bytes(32)

    {:ok, contract_tx_address} =
      Playbook.send_transaction(
        "contract_playbook_seed",
        :transfer,
        %TransactionData{
          ownerships: [
            %Ownership{
              secret: Crypto.aes_encrypt("contract_playbook_seed", secret_key),
              authorized_keys: %{
                storage_node_public_key => Crypto.ec_encrypt(secret_key, storage_node_public_key)
              }
            }
          ],
          code: """
          condition inherit: [
            type: transfer,
            uco_transfers: [
              %{
                to: "#{Base.encode16(recipient_address2)}",
                amount: #{amount_to_send}
              }
            ]
          ]

          actions triggered_by: interval, at: "* * * * * *" do
            set_type transfer
            add_uco_transfer to: "#{Base.encode16(recipient_address2)}", amount: #{amount_to_send}
          end
          """
        },
        host,
        port
      )

    Logger.info(
      "Deployed smart contract #{Base.encode16(contract_tx_address)} to 0.1 UCO to #{Base.encode16(recipient_address2)} each seconds"
    )

    balance =
      Enum.reduce(0..4, 0, fn _i, _acc ->
        Process.sleep(1_000)
        balance = Playbook.get_uco_balance(recipient_address2, host, port)
        Logger.info("#{Base.encode16(recipient_address2)} received #{balance} UCO")
        balance
      end)

    # The recipient address should have received 4 times, 0.1 UCO
    true = balance == 0.4

    :ok
  end
end
