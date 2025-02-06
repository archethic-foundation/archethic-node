defmodule Archethic.Utils.Regression.Benchmark.SmartContractHelper do
  @moduledoc false

  require Logger
  alias Archethic.Utils.Regression.Api

  def await_no_more_calls(contract_address, trigger_address, endpoint) do
    call_utxos =
      contract_address
      |> Api.get_unspent_outputs(endpoint)
      |> Enum.filter(
        &(Map.get(&1, "type") == "call" && Map.get(&1, "from") == Base.encode16(trigger_address))
      )

    case call_utxos do
      [] ->
        :ok

      _ ->
        Logger.debug(
          "Waiting for contract call from #{Base.encode16(trigger_address)} on contract #{Base.encode16(contract_address)}"
        )

        Process.sleep(200)
        await_no_more_calls(contract_address, trigger_address, endpoint)
    end
  end
end
