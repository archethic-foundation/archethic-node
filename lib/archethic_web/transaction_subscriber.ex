defmodule ArchethicWeb.TransactionSubscriber do
  @moduledoc false

  use GenServer

  alias Absinthe.Subscription

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.PubSub
  alias Archethic.TransactionChain.TransactionSummary

  alias ArchethicWeb.Endpoint

  require Logger

  alias Archethic.P2P

  alias Archethic.Election

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a transaction address to monitor
  """
  @spec register(binary(), non_neg_integer()) :: :ok
  def register(tx_address, start_time)
      when is_binary(tx_address) and is_integer(start_time) do
    GenServer.cast(__MODULE__, {:register, tx_address, start_time})
  end

  @doc """
  Report a transaction error
  """
  @spec report_error(atom(), binary()) :: :ok
  def report_error(error, tx_address) when is_binary(tx_address) do
    GenServer.cast(__MODULE__, {:error, tx_address, error})
  end

  def init(_) do
    PubSub.register_to_new_replication_attestations()
    :timer.send_after(5_000, :clean)
    {:ok, %{}}
  end

  def handle_cast(
        {:error, tx_address, error},
        state
      ) do
    Logger.debug("error in processing transaction: #{inspect({tx_address, error})}")

    new_state =
      Map.update(state, tx_address, %{status: :error}, fn state ->
        state
        |> Map.put(:status, :error)
      end)

    Subscription.publish(
      Endpoint,
      %{address: tx_address, error: error},
      transaction_error: tx_address
    )

    {:noreply, new_state}
  end

  def handle_cast({:register, tx_address, start_time}, state) do
    {:noreply,
     Map.put(state, tx_address, %{
       status: :pending,
       start_time: start_time,
       nb_confirmations: 0,
       max_confirmations: get_max_confirmations(tx_address)
     })}
  end

  def handle_info(
        {:new_replication_attestation,
         %ReplicationAttestation{
           confirmations: confirmations,
           transaction_summary: %TransactionSummary{
             address: tx_address
           }
         }},
        state
      ) do
    %{nb_confirmations: nb_confirmations, max_confirmations: max_confirmations} =
      Map.get(state, tx_address, %{nb_confirmations: 0, max_confirmations: 0})

    total_confirmations = nb_confirmations + length(confirmations)

    Subscription.publish(
      Endpoint,
      %{
        address: tx_address,
        nb_confirmations: total_confirmations,
        max_confirmations: max_confirmations
      },
      transaction_confirmed: tx_address
    )

    case Map.get(state, tx_address) do
      nil ->
        {:noreply, state}

      %{status: :confirmed} ->
        new_state =
          Map.update!(state, tx_address, &Map.put(&1, :nb_confirmations, total_confirmations))

        {:noreply, new_state}

      %{status: :pending, start_time: start_time} ->
        :telemetry.execute([:archethic, :transaction_end_to_end_validation], %{
          duration: System.monotonic_time() - start_time
        })

        new_state =
          Map.update!(state, tx_address, fn state ->
            state
            |> Map.put(:status, :confirmed)
            |> Map.put(:nb_confirmations, total_confirmations)
          end)

        {:noreply, new_state}
    end
  end

  def handle_info(:clean, state) do
    now = System.monotonic_time()

    new_state =
      Enum.filter(state, fn
        {_address, %{status: :error}} ->
          false

        {_address, %{status: :confirmed}} ->
          true

        {_address, %{status: :pending, start_time: start_time}} ->
          second_elapsed = System.convert_time_unit(now - start_time, :native, :second)
          second_elapsed <= 3_600
      end)
      |> Enum.into(%{})

    {:noreply, new_state}
  end

  def get_max_confirmations(tx_address) do
    tx_address
    |> Election.chain_storage_nodes(P2P.authorized_nodes())
    |> Enum.count()
  end
end
