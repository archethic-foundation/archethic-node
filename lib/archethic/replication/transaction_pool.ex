defmodule Archethic.Replication.TransactionPool do
  @moduledoc false

  use GenServer
  @vsn 2

  require Logger

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ProofOfValidation

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  def start_link(arg \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, arg, opts)
  end

  @doc """
  Queue the transaction and the inputs used in the validation in the pool
  """
  @spec add_transaction(
          GenServer.server(),
          validated_transaction :: Transaction.t(),
          validation_inputs :: list(VersionedUnspentOutput.t())
        ) :: :ok
  def add_transaction(name \\ __MODULE__, tx = %Transaction{}, validation_inputs)
      when is_list(validation_inputs) do
    GenServer.cast(name, {:add_transaction, tx, validation_inputs})
  end

  @doc """
  Add the proof of validation to the queued transaction
  """
  @spec add_proof_of_validation(
          gen_server :: GenServer.server(),
          proof_of_validation :: ProofOfValidation.t(),
          tx_address :: Crypto.prepended_hash()
        ) :: :ok
  def add_proof_of_validation(name \\ __MODULE__, proof_of_validation, tx_address) do
    GenServer.cast(name, {:add_proof_of_validation, proof_of_validation, tx_address})
  end

  @doc """
  Get the transaction and the inputs for the given transaction's address
  """
  @spec get_transaction(GenServer.server(), address :: Crypto.prepended_hash()) ::
          {:ok, validated_transaction :: Transaction.t(),
           validation_inputs :: list(VersionedUnspentOutput.t())}
          | {:error, :transaction_not_exists}
  def get_transaction(name \\ __MODULE__, address) when is_binary(address) do
    GenServer.call(name, {:get_transaction, address})
  end

  @doc """
  Dequeue the transaction and the inputs for the given transaction's address
  """
  @spec pop_transaction(GenServer.server(), address :: Crypto.prepended_hash()) ::
          {:ok, validated_transaction :: Transaction.t(),
           validation_inputs :: list(VersionedUnspentOutput.t())}
          | {:error, :transaction_not_exists}
  def pop_transaction(name \\ __MODULE__, address) when is_binary(address) do
    GenServer.call(name, {:pop_transaction, address})
  end

  def init(arg) do
    clean_interval = Keyword.get(arg, :clean_interval, 5_000)
    ttl = Keyword.get(arg, :ttl, 60_000)
    clean_ref = Process.send_after(self(), :clean, clean_interval)

    {:ok,
     %{
       ttl: ttl,
       clean_interval: clean_interval,
       clean_ref: clean_ref,
       transactions: %{}
     }}
  end

  def handle_cast(
        {:add_transaction, tx = %Transaction{address: address, type: type}, validation_inputs},
        state = %{ttl: ttl}
      ) do
    expire_at = DateTime.add(DateTime.utc_now(), ttl, :millisecond)

    new_state =
      Map.update!(state, :transactions, &Map.put(&1, address, {tx, expire_at, validation_inputs}))

    Logger.info("Added in the transaction pool",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )

    {:noreply, new_state}
  end

  def handle_cast(
        {:add_proof_of_validation, proof_of_validation, tx_address},
        state
      ) do
    {type, new_state} =
      get_and_update_in(state, [:transactions, tx_address], fn
        {tx = %Transaction{type: type}, expire_at, inputs} ->
          tx = %Transaction{tx | proof_of_validation: proof_of_validation}
          {type, {tx, expire_at, inputs}}

        nil ->
          :pop
      end)

    if is_nil(type) do
      Logger.warning("Cannot add proof to transaction not in pool",
        transaction_address: Base.encode16(tx_address)
      )
    else
      Logger.info("Added in the transaction pool",
        transaction_address: Base.encode16(tx_address),
        transaction_type: type
      )
    end

    {:noreply, new_state}
  end

  def handle_call({:get_transaction, address}, _from, state = %{transactions: transactions}) do
    case Map.get(transactions, address) do
      nil -> {:reply, {:error, :transaction_not_exists}, state}
      {tx, _, validation_inputs} -> {:reply, {:ok, tx, validation_inputs}, state}
    end
  end

  def handle_call({:pop_transaction, address}, _from, state = %{transactions: transactions}) do
    case Map.pop(transactions, address) do
      {nil, _} ->
        {:reply, {:error, :transaction_not_exists}, state}

      {{tx, _, validation_inputs}, rest_transactions} ->
        new_state = Map.put(state, :transactions, rest_transactions)
        {:reply, {:ok, tx, validation_inputs}, new_state}
    end
  end

  def code_change(_, state, _), do: {:ok, state}

  def handle_info(:clean, state = %{clean_interval: clean_interval}) do
    clean_ref = Process.send_after(self(), :clean, clean_interval)

    new_state =
      state
      |> Map.update!(:transactions, fn transactions ->
        Enum.reject(transactions, fn
          {_, {_, expire_at, _}} -> DateTime.compare(DateTime.utc_now(), expire_at) in [:gt, :eq]
        end)
        |> Enum.into(%{})
      end)
      |> Map.put(:clean_ref, clean_ref)

    {:noreply, new_state}
  end
end
