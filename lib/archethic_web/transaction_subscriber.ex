defmodule ArchEthicWeb.TransactionSubscriber do
  @moduledoc false

  use GenServer

  alias Absinthe.Subscription

  alias ArchEthic.BeaconChain.ReplicationAttestation
  alias ArchEthic.PubSub
  alias ArchEthic.TransactionChain.TransactionSummary

  alias ArchEthicWeb.Endpoint

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

  def init(_) do
    PubSub.register_to_new_replication_attestations()
    :timer.send_after(5_000, :clean)
    {:ok, %{}}
  end

  def handle_cast({:register, tx_address, start_time}, state) do
    {:noreply, Map.put(state, tx_address, %{status: :pending, start_time: start_time})}
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
    Subscription.publish(
      Endpoint,
      %{address: tx_address, nb_confirmations: length(confirmations)},
      transaction_confirmed: tx_address
    )

    case Map.pop(state, tx_address) do
      {nil, state} ->
        {:noreply, state}

      {%{status: :pending, start_time: start_time}, state} ->
        :telemetry.execute([:archethic, :transaction_end_to_end_validation], %{
          duration: System.monotonic_time() - start_time
        })

        {:noreply, state}
    end
  end

  def handle_info(:clean, state) do
    now = System.monotonic_time()

    new_state =
      Enum.filter(state, fn {_address, %{status: :pending, start_time: start_time}} ->
        second_elapsed = System.convert_time_unit(now - start_time, :native, :second)
        second_elapsed <= 86_400
      end)
      |> Enum.into(%{})

    {:noreply, new_state}
  end
end
