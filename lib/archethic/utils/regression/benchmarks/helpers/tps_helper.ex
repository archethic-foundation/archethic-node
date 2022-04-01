defmodule ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper do
  @moduledoc """
  Helpers Methods to carry out the TPS benchmarks
  """
  alias ArchEthic.Utils.Regression.Playbook

  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  alias ArchEthic.Crypto

  def withdraw_uco_via_host(recipient_address, host, port, amount) do
    Playbook.send_funds_to(recipient_address, host, port, amount)
  end

  def preliminaries() do
    alice = %{seed: "StupidAlice"}
    bob = %{seed: "IdiotBob"}

    alice = Map.put(alice, :address, get_address(alice.seed))
    bob = Map.put(bob, :address, get_address(bob.seed))

    alice = Map.put(alice, :transaction_data, get_transaction_data(bob.address))
    bob = Map.put(bob, :transaction_data, get_transaction_data(alice.address))

    {alice, bob}
  end

  def get_address(seed) do
    {public_key, _private_key} = Crypto.derive_keypair(seed, 0, Crypto.default_curve())

    Crypto.derive_address(public_key)
  end

  def get_transaction_data(recipient_address) do
    # exchange 100 x 10^-8 uco exchange or 10^-6 uco
    # 10% fees 10^-7
    %TransactionData{
      ledger: %Ledger{
        uco: %UCOLedger{
          transfers: [
            %UCOTransfer{
              to: recipient_address,
              amount: 100
            }
          ]
        }
      }
    }
  end

  def dispatch_transactions(alice, bob, host, port) do
    Playbook.send_transaction(
      alice.seed,
      :transfer,
      alice.transaction_data,
      host,
      port,
      Crypto.default_curve()
    )

    Playbook.send_transaction(
      bob.seed,
      :transfer,
      bob.transaction_data,
      host,
      port,
      Crypto.default_curve()
    )
  end
end
