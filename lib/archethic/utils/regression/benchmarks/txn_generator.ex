defmodule Archethic.Utils.Regression.Benchmark.TxnGenerator do
  @moduledoc false

  require Logger

  alias Archethic
  alias Archethic.Crypto

  # alias ArchethicWeb.TransactionSubscriber
  # alias Archethic.Utils.Regression.Playbook
  alias Archethic.Utils.Regression.Benchmark
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer
  @behaviour Benchmark

  # @pool_seed Application.compile_env(:archethic, [ArchethicWeb.FaucetController, :seed])
  def plan([host | _nodes], _opts) do
    port = Application.get_env(:archethic, ArchethicWeb.Endpoint)[:http][:port]

    {
      %{
        "UCO Transfer single recipient" => fn ->
          benchee(host, port)
        end
      },
      [parallel: 1]
    }
  end

  def benchee(_host, _port) do
    # Enum.map(sender_seed(), &get_address(&1))
    # |> Playbook.batch_send_funds_to(host, port)
    Archethic.Utils.Regression.Benchmark.GetFunds.main()
    Enum.map(seed(), fn {sender_seed, reciever_seed} ->
      Task.async(fn ->
        build_txn(sender_seed, reciever_seed)
        |> deploy()
      end)
    end)
    |> Enum.map(&Task.await/1)
  end

  def seed() do
    Enum.map(Enum.to_list(1..10_000), fn x ->
      {"sender_seed #{x}", "receiver seed #{x}"}
    end)
  end

  def sender_seed() do
    Enum.map(Enum.to_list(1..10_000), fn x ->
      "sender_seed #{x}"
    end)
  end

  def receiver_seed() do
    Enum.map(Enum.to_list(1..10_000), fn x ->
      "reciever_seed #{x}"
    end)
  end

  def get_address(seed) do
    seed
    |> Crypto.derive_keypair(0)
    |> elem(0)
    |> Crypto.derive_address()
  end

  def deploy(txn) do
    case Archethic.send_new_transaction(txn) do
      :ok ->
        {:ok, txn.address}
        Logger.critical("success #{inspect(txn.address)}")

      {:error, _} = e ->
        e
    end
  end

  def build_txn(ss, rs) do
    txn_data = get_txn_data(rs)
    Transaction.new(:transfer, txn_data, ss, 0, Crypto.default_curve())
  end

  defp get_txn_data(receiver_seed) do
    recipient_address =
      receiver_seed
      |> Crypto.derive_keypair(0)
      |> elem(0)
      |> Crypto.derive_address()

    %TransactionData{
      ledger: %Ledger{
        uco: %UCOLedger{
          transfers: [
            %UCOTransfer{
              to: recipient_address,
              amount: 10
            }
          ]
        }
      }
    }
  end
end
