defmodule Archethic.Replication.TransactionPool do
  @moduledoc false

  use GenServer
  @vsn 2

  require Logger

  alias Archethic.TransactionChain.Transaction

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
  Dequeue the transaction and the inputs for the given transaction's address
  """
  @spec pop_transaction(GenServer.server(), binary()) ::
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

  def handle_call({:pop_transaction, address}, _from, state = %{transactions: transactions}) do
    case Map.pop(transactions, address) do
      {nil, _} ->
        {:reply, {:error, :transaction_not_exists}, state}

      {{transaction, _, validation_inputs}, rest_transactions} ->
        {:reply, {:ok, transaction, validation_inputs},
         %{state | transactions: rest_transactions}}
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
