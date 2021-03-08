defmodule Uniris.Contracts.Loader do
  @moduledoc false

  alias Uniris.ContractRegistry
  alias Uniris.ContractSupervisor

  alias Uniris.Contracts.Contract
  alias Uniris.Contracts.TransactionLookup
  alias Uniris.Contracts.Worker

  alias Uniris.Crypto

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData

  require Logger

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    TransactionChain.list_all([:address, :previous_public_key, data: [:code]])
    |> Stream.filter(&(&1.data.code != ""))
    |> Stream.each(&load_transaction(&1, true))
    |> Stream.run()

    {:ok, []}
  end

  @doc """
  Load the smart contracts based on transaction involving smart contract code
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(_tx, from_db \\ false)

  def load_transaction(
        tx = %Transaction{
          address: address,
          data: %TransactionData{code: code},
          previous_public_key: previous_public_key
        },
        _from_db
      )
      when code != "" do
    stop_contract(Crypto.hash(previous_public_key))

    {:ok, _} =
      DynamicSupervisor.start_child(
        ContractSupervisor,
        {Worker, Contract.from_transaction!(tx)}
      )

    Logger.info("Smart contract loaded", transaction: Base.encode16(address))
  end

  def load_transaction(
        tx = %Transaction{
          address: tx_address,
          timestamp: tx_timestamp,
          validation_stamp: %ValidationStamp{recipients: recipients}
        },
        false
      )
      when recipients != [] do
    Enum.each(recipients, fn contract_address ->
      case Worker.execute(contract_address, tx) do
        :ok ->
          TransactionLookup.add_contract_transaction(contract_address, tx_address, tx_timestamp)

        _ ->
          :ok
      end
    end)
  end

  def load_transaction(
        %Transaction{
          address: address,
          timestamp: timestamp,
          validation_stamp: %ValidationStamp{recipients: recipients}
        },
        true
      )
      when recipients != [] do
    Enum.each(recipients, &TransactionLookup.add_contract_transaction(&1, address, timestamp))
  end

  def load_transaction(_tx, _), do: :ok

  @doc """
  Termine a contract execution
  """
  @spec stop_contract(binary()) :: :ok
  def stop_contract(address) when is_binary(address) do
    case Registry.lookup(ContractRegistry, address) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(ContractSupervisor, pid)

      _ ->
        :ok
    end
  end
end
