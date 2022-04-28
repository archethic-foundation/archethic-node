defmodule ArchEthic.Utils.Regression.Benchmark.NodeThroughput do
  @moduledoc """
  Using Publically exposed Api To Benchmark
  """
  require Logger

  # alias modules
  alias ArchEthic.Utils.Regression.Benchmark
  alias ArchEthic.Utils.WSClient
  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  # behaviour
  @behaviour Benchmark

  def faucet_enabled?(),
    do: {
      :ok,
      # System.get_env("ARCHETHIC_NETWORK_TYPE") == "testnet"}
      true
    }

  def plan([host | _nodes], _opts) do
    port = Application.get_env(:archethic, ArchEthicWeb.Endpoint)[:http][:port]

    Logger.info("Starting Benchmark: Transactions Per Seconds at host #{host} and port #{port}")

    scenario = %{
      "One to One Random wallet Transfers" => fn -> benchmark(host, port) end
    }

    opts = [
      print: [benchmarking: true],
      formatters: [
        {Benchee.Formatters.Console, extended_statistics: true}
      ],
      parallel: 1
    ]

    {scenario, opts}
  end

  def benchmark(host, port) do
    # does not accept wss
    WSClient.start_ws_client(host: host, port: port)
    via_playbook(host, port)
  end

  def via_playbook(host, port) do
    alias ArchEthic.Utils.Regression.Playbook

    {sender_seed, receiver_seed} = {random_seed(), random_seed()}

    sender_seed
    |> derive_keypair()
    |> acquire_genesis_address()
    |> Playbook.send_funds_to(host, port)

    recipient_address =
      receiver_seed
      |> derive_keypair()
      |> acquire_genesis_address()

    txn_data = %TransactionData{
      ledger: %Ledger{
        uco: %UCOLedger{
          transfers: [
            %UCOTransfer{
              to: recipient_address,
              amount: 1_000_000
            }
          ]
        }
      }
    }

    Playbook.send_transaction(sender_seed, :transfer, txn_data, host, port)
  end

  def get_curve(), do: Crypto.default_curve()

  def random_seed(), do: Integer.to_string(System.unique_integer([:monotonic]))

  def derive_keypair(seed, index \\ 0), do: Crypto.derive_keypair(seed, index, get_curve())

  def acquire_genesis_address({pbKey, _privKey}), do: Crypto.derive_address(pbKey)

  def get_address(pbKey), do: Crypto.derive_address(pbKey)

  def prepare_query(txn_address),
    do: """
    subscription {
      transactionConfirmed(address:
        "#{txn_address}") {
        nbConfirmations
      }
    }
    """

  def await_replication(txn_address) do
    Task.async(fn ->
      WSClient.absinthe_sub(
        prepare_query(txn_address),
        _var = %{},
        _pid = self(),
        _sub_id = txn_address
      )

      data =
        receive do
          msg ->
            Logger.debug("#{inspect(txn_address)}|#{inspect(msg)}")
            msg
        end

      case data do
        %{"transactionConfirmed" => %{"nbConfirmations" => 1}} -> {:ok, :success}
        data -> {:error, error_info: data}
      end
    end)
  end
end
