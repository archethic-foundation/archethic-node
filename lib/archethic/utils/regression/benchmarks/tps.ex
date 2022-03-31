defmodule ArchEthic.Utils.Regression.Benchmark.TPS do
  @moduledoc """
  Module for regession testing the paralleing processing of transactions and
  benchmarking the parallel transaction processing capability of a node
  """

  require Logger

  alias ArchEthic.Utils.Regression.Benchmark
  alias ArchEthic.Utils.Regression.Playbook
  alias ArchEthic.Crypto
  alias ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper

  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  @behaviour Benchmark

  def plan([host | _nodes], _opts) do
    port = Application.get_env(:archethic, ArchEthic.P2P.Listener)[:port]

    {alice, bob} = preliminaries()

    TPSHelper.withdraw_uco_from_testnet_endpoint(alice.address)
    TPSHelper.withdraw_uco_from_testnet_endpoint(bob.address)

    dispatch_transactions(alice, bob, host, port)
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
    {next_public_key, _next_private_key} =
      Crypto.derive_keypair(seed, 0 + 1, Crypto.default_curve())

    Crypto.derive_address(next_public_key)
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

  def benchmark(alice, bob, host, port) do
    Task.async_stream(
      1..3,
      fn _x ->
        dispatch_transactions(alice, bob, host, port)
      end,
      max_concurrenct: System.schedulers_online() * 10
    )
  end
end
