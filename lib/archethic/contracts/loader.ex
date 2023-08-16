defmodule Archethic.Contracts.Loader do
  @moduledoc false

  alias Archethic.ContractRegistry
  alias Archethic.ContractSupervisor

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.TransactionLookup
  alias Archethic.Contracts.Worker

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  require Logger

  use GenServer
  @vsn Mix.Project.config()[:version]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    TransactionChain.list_io_transactions([])
    |> Stream.filter(&(&1.data.recipients != []))
    |> Stream.each(&load_transaction(&1, execute_contract?: false, io_transaction?: true))
    |> Stream.run()

    # Network transactions does not contains trigger or recipient
    TransactionChain.list_all([])
    |> Stream.reject(&Transaction.network_type?(&1.type))
    |> Stream.filter(&(&1.data.recipients != [] or &1.data.code != ""))
    |> Stream.each(&load_transaction(&1, execute_contract?: false, io_transaction?: false))
    |> Stream.run()

    {:ok, []}
  end

  @doc """
  Load the smart contracts based on transaction involving smart contract code
  """
  @spec load_transaction(Transaction.t(), list()) :: :ok
  def load_transaction(
        tx = %Transaction{
          address: address,
          type: type,
          data: %TransactionData{
            code: code,
            recipients: recipients
          },
          validation_stamp: %ValidationStamp{
            recipients: resolved_recipients,
            timestamp: timestamp,
            protocol_version: protocol_version
          }
        },
        execute_contract?: execute_contract?,
        io_transaction?: io_transaction?
      ) do
    # Stop previous transaction contract
    stop_contract(Transaction.previous_address(tx))

    # If transaction contains code and we are storage node, start a new worker for it
    if code != "" and not io_transaction? do
      %Contract{triggers: triggers} = Contracts.parse!(code)
      triggers = Enum.reject(triggers, fn {_, actions} -> actions == {:__block__, [], []} end)

      # Create worker only load smart contract which are expecting interactions and where the actions are not empty
      if length(triggers) > 0 do
        {:ok, _} =
          DynamicSupervisor.start_child(
            ContractSupervisor,
            {Worker, Contract.from_transaction!(tx)}
          )

        Logger.info("Smart contract loaded",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )
      end
    end

    # For each recipients, load the transaction in lookup and execute the contract
    recipients
    |> Enum.zip(resolved_recipients)
    |> Enum.each(fn {recipient, contract_address} ->
      TransactionLookup.add_contract_transaction(
        contract_address,
        address,
        timestamp,
        protocol_version
      )

      if execute_contract? do
        # execute contract asynchronously only if we are in live replication
        Logger.info(
          "Execute transaction on contract #{Base.encode16(contract_address)}",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )

        Worker.execute(contract_address, tx, recipient)
      end

      Logger.info("Transaction towards contract ingested",
        transaction_address: Base.encode16(address),
        transaction_type: type
      )
    end)
  end

  @doc """
  Termine a contract execution
  """
  @spec stop_contract(binary()) :: :ok
  def stop_contract(address) when is_binary(address) do
    case Registry.lookup(ContractRegistry, address) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(ContractSupervisor, pid)
        TransactionLookup.clear_contract_transactions(address)
        TransactionChain.clear_pending_transactions(address)
        Logger.info("Stop smart contract at #{Base.encode16(address)}")

      _ ->
        :ok
    end
  end
end
