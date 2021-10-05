defmodule ArchEthic.Contracts.Loader do
  @moduledoc false

  alias ArchEthic.ContractRegistry
  alias ArchEthic.ContractSupervisor

  alias ArchEthic.Contracts
  alias ArchEthic.Contracts.Contract
  alias ArchEthic.Contracts.TransactionLookup
  alias ArchEthic.Contracts.Worker

  alias ArchEthic.DB

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.TransactionData

  require Logger

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    DB.list_last_transaction_addresses()
    |> Stream.map(fn address ->
      {:ok, tx} =
        DB.get_transaction(address, [
          :address,
          :previous_public_key,
          :data,
          validation_stamp: [:timestamp]
        ])

      tx
    end)
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
          type: type,
          data: %TransactionData{code: code}
        },
        _from_db
      )
      when code != "" do
    stop_contract(Transaction.previous_address(tx))

    case Contracts.parse!(code) do
      # Only load smart contract which are expecting interactions
      %Contract{triggers: triggers = [_ | _]} ->
        triggers = Enum.reject(triggers, &(&1.actions == {:__block__, [], []}))

        # Avoid to load empty smart contract
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

      _ ->
        :ok
    end
  end

  def load_transaction(
        tx = %Transaction{
          address: tx_address,
          type: tx_type,
          validation_stamp: %ValidationStamp{timestamp: tx_timestamp, recipients: recipients}
        },
        false
      )
      when recipients != [] do
    Enum.each(recipients, fn contract_address ->
      Logger.info("Execute transaction on contract #{Base.encode16(contract_address)}",
        transaction_address: Base.encode16(tx_address),
        transaction_type: tx_type
      )

      case Worker.execute(contract_address, tx) do
        :ok ->
          TransactionLookup.add_contract_transaction(contract_address, tx_address, tx_timestamp)

          Logger.info("Transaction towards contract ingested",
            transaction_address: Base.encode16(tx_address),
            transaction_type: tx_type
          )

        _ ->
          :ok
      end
    end)
  end

  def load_transaction(
        %Transaction{
          address: address,
          type: type,
          validation_stamp: %ValidationStamp{recipients: recipients, timestamp: timestamp}
        },
        true
      )
      when recipients != [] do
    Enum.each(recipients, &TransactionLookup.add_contract_transaction(&1, address, timestamp))

    Logger.info("Transaction towards contract ingested",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )
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
        Logger.info("Stop smart contract at #{Base.encode16(address)}")

      _ ->
        :ok
    end
  end
end
