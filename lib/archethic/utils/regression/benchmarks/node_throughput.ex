defmodule ArchEthic.Utils.Regression.Benchmark.NodeThroughput do
  @moduledoc """
  Using Publically exposed Api To Benchmark
  """
  require Logger

  # alias modules
  alias ArchEthic.Utils.Regression.Benchmark
  alias ArchEthic.Utils.WSClient
  alias ArchEthic.Crypto
  alias ArchEthic.Utils.Regression.Playbook
  alias ArchEthic.Utils.Regression.Benchmark.SeedProcess

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
      parallel: 10
    ]

    {scenario, opts}
  end

  def benchmark(host, port) do
    run_benchee(host, port)
    # does not accept wss
    # WSClient.start_ws_client(host: host, port: port)
    # via_playbook(host, port)
  end

  def via_playbook(host, port) do
    {sender_seed, receiver_seed} = {random_seed(), random_seed()}

    sender_seed
    |> derive_keypair()
    |> acquire_genesis_address()
    |> Playbook.send_funds_to(host, port, 1_000_000)

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

      receive do
        message ->
          case message do
            %{"transactionConfirmed" => %{"nbConfirmations" => 1}} -> :ok
            _data -> :error
          end

          Logger.debug("#{inspect(txn_address)}|#{inspect(message)}")
      after
        15_000 ->
          Logger.debug("timeout")
          :timeout
      end
    end)
  end

  @doc """
    generates a random valued map of
    %{index => {senderseed,reciever seed}}
  """
  def map_index_with_seed() do
    Enum.map(0..1000, fn i -> {i, "sender_seed_A_#{i}", "reciever_seed_B_#{i}"} end)
    |> Enum.into(%{}, fn {index, sender, reciever} -> {index, {sender, reciever}} end)
  end

  def allocate_funds(seeds, host, port, amount \\ 100) do
    recipient_addresses =
      Enum.map(
        seeds,
        fn {_index, {sender_seed, _reciever_seed}} ->
          sender_seed
          |> derive_keypair()
          |> acquire_genesis_address()
        end
      )

    Playbook.batch_send_funds_to(recipient_addresses, host, port, amount)
  end

  def get_txn_data(receiver_seed) do
    recipient_address =
      receiver_seed
      |> derive_keypair()
      |> acquire_genesis_address()

    %TransactionData{
      ledger: %Ledger{
        uco: %UCOLedger{
          transfers: [
            %UCOTransfer{
              to: recipient_address,
              amount: 1_000
            }
          ]
        }
      }
    }
  end

  def completion_a_to_b(pid, host, port) do
    {index, seeds} = SeedProcess.pop_seed(pid)
    {sender_seed, receiver_seed} = seeds

    Playbook.send_transaction_with_await_replication(
      sender_seed,
      :transfer,
      get_txn_data(receiver_seed),
      host,
      port
    )

    SeedProcess.put_seed(pid, index, seeds)
  end

  def ingestion_a_to_b(pid, host, port) do
    {index, seeds} = SeedProcess.pop_seed(pid)
    {sender_seed, receiver_seed} = seeds

    Playbook.send_transaction(
      sender_seed,
      :transfer,
      get_txn_data(receiver_seed),
      host,
      port
    )

    SeedProcess.put_seed(pid, index, seeds)
  end

  def run_benchee(host, port) do
    {:ok, pid} = SeedProcess.start_link(seeds: map_index_with_seed())
    WSClient.start_ws_client(host: host, port: port)

    Benchee.run(
      %{
        "Completion" => fn ->
          1..5
          |> Enum.map(fn _x -> Task.async(fn -> completion_a_to_b(pid, host, port) end) end)
          |> Enum.map(&Task.await/1)
        end,
        "Ingestion" => fn ->
          1..10
          |> Enum.map(fn _x -> Task.async(fn -> ingestion_a_to_b(pid, host, port) end) end)
          |> Enum.map(&Task.await/1)
        end
      },
      parallel: 100,
      before_scenario: fn -> 
         allocate_funds( SeedProcess.get_state(pid), host, port)
      end) 
    )
  end
end
