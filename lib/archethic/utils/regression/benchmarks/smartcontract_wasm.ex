defmodule Archethic.Utils.Regression.Benchmark.WasmSmartContractTrigger do
  @moduledoc false

  require Logger

  alias Archethic.Crypto

  alias Archethic.Utils.Regression.Api
  alias Archethic.Utils.Regression.Playbook.SmartContract
  alias Archethic.Utils.Regression.Benchmark.SeedHolder
  alias Archethic.Utils.Regression.Benchmark.SmartContractHelper
  alias Archethic.Utils.Regression.Benchmark
  alias Archethic.Utils.WebSocket.Client, as: WSClient
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.TransactionChain.TransactionData

  @behaviour Benchmark
  def plan([host | _nodes], _opts) do
    port = Application.get_env(:archethic, ArchethicWeb.Endpoint)[:http][:port]

    endpoint = %Api{host: host, port: port, protocol: :http}

    WSClient.start_link(host: host, port: port)
    Crypto.Ed25519.LibSodiumPort.start_link()
    Logger.info("Starting Benchmark: Transactions Per Seconds at host #{host} and port #{port}")

    storage_nonce_pubkey = Api.get_storage_nonce_public_key(endpoint)

    {:ok, pid} =
      SeedHolder.start_link(seeds: Enum.map(0..200, fn _ -> :crypto.strong_rand_bytes(32) end))

    amount = 10

    contract_seed = :crypto.strong_rand_bytes(32)

    genesis_address =
      Crypto.derive_keypair(contract_seed, 0) |> elem(0) |> Crypto.derive_address()

    Api.send_funds_to_seeds(
      [contract_seed | SeedHolder.get_seeds(pid)]
      |> Enum.map(fn seed -> {seed, amount} end)
      |> Enum.into(%{}),
      endpoint
    )

    contract_address =
      SmartContract.deploy(
        contract_seed,
        %TransactionData{
          contract:
            SmartContract.read_wasm_contract(
              "lib/archethic/utils/regression/playbooks/smart_contract/wasm_counter.wasm",
              "lib/archethic/utils/regression/playbooks/smart_contract/wasm_counter.manifest.json"
            )
        },
        storage_nonce_pubkey,
        endpoint
      )

    {
      %{
        "Wasm SC trigger" => fn ->
          {trigger_seed, _} = SeedHolder.pop_seed(pid)

          {:ok, trigger_address} =
            SmartContract.trigger(trigger_seed, contract_address, endpoint,
              recipients: [%Recipient{action: "inc", address: contract_address, args: %{}}],
              await_timeout: 60_000,
              version: 4
            )

          SmartContractHelper.await_no_more_calls(genesis_address, trigger_address, endpoint)
          :cprof.stop()
        end
      },
      [parallel: 4]
    }
  end
end
