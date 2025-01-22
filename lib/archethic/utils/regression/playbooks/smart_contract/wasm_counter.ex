defmodule Archethic.Utils.Regression.Playbook.SmartContract.WasmCounter do
  @moduledoc """
  This contract is triggered by transactions
  It starts with content=0 and the number will increment for each transaction received
  """

  alias Archethic.Crypto
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.Utils.Regression.Api
  alias Archethic.Utils.Regression.Playbook.SmartContract
  alias Archethic.TransactionChain.TransactionData.Recipient

  require Logger

  def play(storage_nonce_pubkey, endpoint) do
    Logger.info("============== CONTRACT: WASM COUNTER ==============")
    contract_seed = SmartContract.random_seed()

    triggers_seeds = Enum.map(1..100, fn _ -> SmartContract.random_seed() end)

    initial_funds =
      Enum.reduce(triggers_seeds, %{contract_seed => 10}, fn seed, acc ->
        Map.put(acc, seed, 10)
      end)

    Api.send_funds_to_seeds(initial_funds, endpoint)

    genesis_address =
      Crypto.derive_keypair(contract_seed, 0) |> elem(0) |> Crypto.derive_address()

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

    nb_transactions = 100

    Enum.map(1..nb_transactions, fn i ->
      Task.async(fn ->
        SmartContract.trigger(
          Enum.at(triggers_seeds, i - 1),
          contract_address,
          endpoint,
          recipients: [%Recipient{action: "inc", address: contract_address, args: %{}}],
          await_timeout: 60_000,
          version: 4
        )
      end)
    end)
    |> Task.await_many(:infinity)

    SmartContract.await_no_more_calls(genesis_address, endpoint)
    unspent_outputs = Api.get_unspent_outputs(genesis_address, endpoint)

    counter =
      case List.first(unspent_outputs) do
        %{"state" => %{"counter" => counter}} -> counter
        %{} -> nil
      end

    case counter do
      ^nb_transactions ->
        Logger.info("Smart contract 'counter' content has been incremented successfully")
        :ok

      content ->
        Logger.error("Smart contract 'counter' content is not as expected: #{content}")
        :error
    end
  end
end
