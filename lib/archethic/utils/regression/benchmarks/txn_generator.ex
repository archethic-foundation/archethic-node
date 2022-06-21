defmodule Archethic.Utils.Regression.Benchmark.TxnGenerator do
  @moduledoc false

  require Logger

  alias Archethic
  alias Archethic.Crypto
  # alias ArchethicWeb.TransactionSubscriber
  alias Archethic.Utils.Regression.Playbook
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
      [parallel: 4]
    }
  end

  def benchee(host, port) do
    {ss, rs} = get_random_seed()
    {sa, _ra} = {ss, rs} |> get_address()

    allocate_funds(sa, host, port)

    Task.async_stream(Enum.to_list(1..100), fn _x ->
      build_txn(ss, rs)
      |> deploy()
    end)
  end

  def get_random_seed() do
    {Integer.to_string(System.unique_integer([:monotonic])),
     Integer.to_string(System.unique_integer([:monotonic]))}
  end

  def get_address({ss, rs}) do
    sa =
      ss
      |> Crypto.derive_keypair(0)
      |> elem(0)
      |> Crypto.derive_address()

    ra =
      rs
      |> Crypto.derive_keypair(0)
      |> elem(0)
      |> Crypto.derive_address()

    {sa, ra}
  end

  def allocate_funds(recipient_address, host, port) do
    Playbook.send_funds_to(recipient_address, host, port)
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
    # genesis_origin_private_key = get_origin_private_key(host, port)

    # tx =
    #   %Transaction{
    #     address: Crypto.derive_address(next_public_key),
    #     type: tx_type,
    #     data: transaction_data,
    #     previous_public_key: previous_public_key
    #   }
    #   |> Transaction.previous_sign_transaction(previous_private_key)
    #   |> Transaction.origin_sign_transaction(genesis_origin_private_key)
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
