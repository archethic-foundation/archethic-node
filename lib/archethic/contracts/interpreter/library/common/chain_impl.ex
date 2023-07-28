defmodule Archethic.Contracts.Interpreter.Library.Common.ChainImpl do
  @moduledoc false

  alias Archethic.Contracts.Interpreter.Legacy
  alias Archethic.Contracts.Interpreter.Library.Common.Chain
  alias Archethic.Contracts.Interpreter.Legacy.UtilsInterpreter
  alias Archethic.Contracts.ContractConstants, as: Constants

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  @behaviour Chain

  @impl Chain
  defdelegate get_genesis_address(address),
    to: Legacy.Library,
    as: :get_genesis_address

  @impl Chain
  def get_first_transaction_address(address) do
    try do
      Legacy.Library.get_first_transaction_address(address)
    rescue
      _ -> nil
    end
  end

  @impl Chain
  def get_genesis_public_key(public_key) do
    try do
      Legacy.Library.get_genesis_public_key(public_key)
    rescue
      _ -> nil
    end
  end

  @impl Chain
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

  @impl Chain
  def get_burn_address(), do: LedgerOperations.burning_address() |> Base.encode16()
end
