defmodule Archethic.Contracts.Interpreter.Library.Common.ChainImpl do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library.Common.Chain

  alias Archethic.Contracts.Interpreter.Legacy
  alias Archethic.Contracts.Interpreter.Legacy.UtilsInterpreter
  alias Archethic.Contracts.ContractConstants, as: Constants

  @impl Archethic.Contracts.Interpreter.Library.Common.Chain
  defdelegate get_genesis_address(address),
    to: Legacy.Library,
    as: :get_genesis_address

  @impl Archethic.Contracts.Interpreter.Library.Common.Chain
  defdelegate get_first_transaction_address(address),
    to: Legacy.Library,
    as: :get_first_transaction_address

  @impl Archethic.Contracts.Interpreter.Library.Common.Chain
  defdelegate get_genesis_public_key(public_key),
    to: Legacy.Library,
    as: :get_genesis_public_key

  @impl Archethic.Contracts.Interpreter.Library.Common.Chain
  def get_transaction(address) do
    address
    |> UtilsInterpreter.get_address("Chain.get_transaction/1")
    |> Archethic.search_transaction()
    |> then(fn
      {:ok, tx} ->
        Constants.from_transaction(tx)

      {:error, _} ->
        nil
    end)
  end
end
