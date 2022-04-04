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

  # get dummy uco from the host
  def withdraw_uco_via_host(recipient_address, host, port, amount) do
    Playbook.send_funds_to(recipient_address, host, port, amount)
  end

  # deploys a transaction
  def send_transaction({{sender_seed, transaction_data}, host, port}) do
    Playbook.send_transaction(
      sender_seed,
      :transfer,
      transaction_data,
      host,
      port,
      Crypto.default_curve()
    )
  end

  # creates a sender and reciever address and seed for benchmarking function
  # this function is executed before each benchmark function call
  # whatever parameter it returns is used for input in benchmark function
  def before_each_scenario_instance({host, port}) do
    # Random seed generation
    # System.unqiuew give unquire value for each runtime
    sender_seed = Integer.to_string(Enum.random(1..1_000_000_000_000))

    {sender_public_key, _private_key} =
      Crypto.derive_keypair(sender_seed, 0, Crypto.default_curve())

    sender_address = Crypto.derive_address(sender_public_key)
    withdraw_uco_via_host(sender_address, host, port, 10)

    recipient_seed = Integer.to_string(Enum.random(1..1_000_000_000_000))

    {recipient_public_key, _private_key} =
      Crypto.derive_keypair(recipient_seed, 0, Crypto.default_curve())

    recipient_address = Crypto.derive_address(recipient_public_key)

    # send dummy uco to recipient
    transaction_data = get_transaction_data(recipient_address)
    {{sender_seed, transaction_data}, host, port}
  end

  def get_transaction_data(recipient_address) do
    %TransactionData{
      ledger: %Ledger{
        uco: %UCOLedger{
          transfers: [
            %UCOTransfer{
              to: recipient_address,
              amount: 10_000
            }
          ]
        }
      }
    }
  end
end

# def pmap(collection, func) do
#   collection
#   |> Enum.map(&Task.async(fn -> func.(&1) end))
#   |> Enum.map(&Task.await/1)
# end
# def before_txn(_recipient_address, host, port, amount) do
#   {recipient_public_key, _private_key} = Crypto.derive_keypair("sender_seed", 0, Crypto.default_curve())
#   recipient_address =  Crypto.derive_address(recipient_public_key)
#   transaction_data  =  get_transaction_data(recipient_address)

#   seed_list = pmap(1..100, fn x ->
#     seed = x * System.unique_integer([:positive])
#     {public_key, _private_key} = Crypto.derive_keypair(seed, 0, Crypto.default_curve())
#     withdraw_uco_via_host(Crypto.derive_address(public_key), host, port, amount)
#     seed
#   end)

#   {seed_list, transaction_data}
# end

# def dispatch_transactions(alice, bob, host, port) do
#   Playbook.send_transaction(
#     alice.seed,
#     :transfer,
#     alice.transaction_data,
#     host,
#     port,
#     Crypto.default_curve()
#   )

#   Playbook.send_transaction(
#     bob.seed,
#     :transfer,
#     bob.transaction_data,
#     host,
#     port,
#     Crypto.default_curve()
#   )
# end
