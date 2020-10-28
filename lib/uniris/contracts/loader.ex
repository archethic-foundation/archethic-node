defmodule Uniris.Contracts.Loader do
  @moduledoc false

  alias Uniris.Contracts.Contract
  alias Uniris.Contracts.Worker

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  require Logger

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    TransactionChain.list_all(data: [:code])
    |> Stream.filter(fn %Transaction{data: %TransactionData{code: code}} ->
      code != ""
    end)
    |> Stream.each(&load_transaction/1)
    |> Stream.run()

    {:ok, []}
  end

  @doc """
  Load the smart contracts based on transaction involving smart contract code
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(tx = %Transaction{address: address, data: %TransactionData{code: code}})
      when code != "" do
    DynamicSupervisor.start_child(ContractSupervisor, {Worker, Contract.from_transaction!(tx)})

    Logger.info("Smart contract loaded", transaction: Base.encode16(address))
  end

  def load_transaction(_), do: :ok
end
