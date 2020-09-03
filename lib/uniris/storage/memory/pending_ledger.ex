defmodule Uniris.Storage.Memory.PendingLedger do
  @moduledoc false

  @table_name :uniris_pending_ledger

  alias Uniris.Interpreter.AST, as: ContractAST
  alias Uniris.Interpreter.Contract

  alias Uniris.Storage.Backend, as: DB

  alias Uniris.Transaction
  alias Uniris.TransactionData

  use GenServer

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_args) do
    Logger.info("Initialize InMemory Pending Ledger...")

    :ets.new(@table_name, [:bag, :named_table, :public, read_concurrency: true])

    DB.list_transaction_chains_info()
    |> Stream.map(fn {address, _} ->
      {:ok, tx} = DB.get_transaction(address, [:address, :type, [:data, [:code, :recipients]]])
      tx
    end)
    |> Stream.filter(&match_transaction?/1)
    |> Stream.each(&load_transaction/1)
    |> Stream.run()

    {:ok, []}
  end

  defp match_transaction?(tx = %Transaction{type: type, data: %TransactionData{code: code}}) do
    cond do
      type == :code_proposal ->
        true

      code != "" ->
        %Contract{conditions: [response: response_conditions]} =
          code
          |> ContractAST.parse()
          |> Contract.from_ast(tx)

        response_conditions != nil

      true ->
        false
    end
  end

  def load_transaction(%Transaction{
        address: address,
        data: %TransactionData{recipients: recipients}
      }) do
    case recipients do
      [] ->
        add_address(address)

      _ ->
        Enum.each(recipients, &add_signature(&1, address))
    end
  end

  @doc """
  Add a transaction address as pending. 
  """
  @spec add_address(address :: binary()) :: :ok
  def add_address(address) when is_binary(address) do
    true = :ets.insert(@table_name, {address, address})
    :ok
  end

  @doc """
  Add a signature to a pending transaction.

  The address of the transaction act as signature
  The previous public key is used to determine the previous signing
  """
  @spec add_signature(pending_tx_address :: binary(), signature_address :: binary()) :: :ok
  def add_signature(pending_tx_address, signature_address)
      when is_binary(pending_tx_address) and is_binary(signature_address) do
    true = :ets.insert(@table_name, {pending_tx_address, signature_address})
    :ok
  end

  @doc """
  Determines if an public key has already a sign for the pending transaction address
  """
  @spec already_signed?(binary(), binary()) :: boolean()
  def already_signed?(address, signature_address) do
    case :ets.lookup(@table_name, address) do
      [] ->
        false

      res ->
        !res
        |> Enum.map(fn {_, signature} -> signature end)
        |> Enum.any?(&(&1 == signature_address))
    end
  end

  @doc """
  Get the list of counter signature for the pending transaction address.

  The counter signatures are transaction addresses validating the the pending transaction
  """
  @spec list_signatures(binary()) :: list(binary())
  def list_signatures(address) when is_binary(address) do
    case :ets.lookup(@table_name, address) do
      [{_, signatures}] ->
        signatures

      [] ->
        []
    end
  end

  @doc """
  Remove a transaction for being a pending one
  """
  @spec remove_address(binary()) :: :ok
  def remove_address(address) when is_binary(address) do
    true = :ets.delete(@table_name, address)
    :ok
  end
end
