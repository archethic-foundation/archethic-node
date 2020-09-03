defmodule Uniris.SharedSecretsRenewal do
  @moduledoc """
  Handle renewal of node shared secrets at a given interval of time.

  At each interval - trigger offset , a new node shared secrets transaction is created including
  the new authorized nodes and is broadcasted to the validation nodes to include
  them as new authorized nodes and update the daily nonce seed.

  Once done, the storage layer will trigger the scheduling of the application of the
  new authorized nodes at the given interval time.
    
  For example, for a interval every day (00:00), with 10min offset.
  At 23:50 UTC, an elected node will build and send the transaction for the renewal
  At 00:00 UTC, all the nodes will apply the changes
  At 00:02 UTC, new authorized nodes are elected for validation

  """
  alias Uniris.Crypto

  alias __MODULE__.NodeRenewal

  alias Uniris.Utils

  use GenServer

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(interval: interval, trigger_offset: trigger_offset) do
    # Schedule the node shared secrets renewal
    Task.start(fn ->
      interval
      |> next_renewal_offset(trigger_offset)
      |> schedule_node_renewal
    end)

    {:ok, %{interval: interval, trigger_offset: trigger_offset}}
  end

  def handle_call(
        {:schedule_node_renewal_application, nodes, encrypted_key, secret, authorization_date},
        _from,
        state = %{interval: interval}
      ) do
    next_time = next_renewal_offset(interval, 0)

    timer =
      case Map.get(state, :timer) do
        nil ->
          Process.send_after(self(), :apply_node_renewal, next_time * 1000)

        ref ->
          Process.cancel_timer(ref)
          Process.send_after(self(), :apply_node_renewal, next_time * 1000)
      end

    new_state =
      state
      |> Map.put(:timer, timer)
      |> Map.put(:authorized_nodes, nodes)
      |> Map.put(:encrypted_key, encrypted_key)
      |> Map.put(:secret, secret)
      |> Map.put(:authorization_date, authorization_date)

    {:reply, :ok, new_state}
  end

  def handle_info(
        :start_node_renewal,
        state = %{interval: interval, trigger_offset: trigger_offset}
      ) do
    Logger.info("Node shared secret key renewal")

    # Schedule the next node shared secrets renewal
    Task.start(fn ->
      interval
      |> next_renewal_offset(trigger_offset)
      |> schedule_node_renewal
    end)

    if NodeRenewal.initiator?() do
      NodeRenewal.send_transaction()
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        :apply_node_renewal,
        state = %{
          authorized_nodes: authorized_nodes,
          encrypted_key: encrypted_key,
          secret: secret,
          authorization_date: authorization_date
        }
      ) do
    NodeRenewal.apply(authorized_nodes, authorization_date, encrypted_key, secret)

    new_state =
      state
      |> Map.delete(:authorized_nodes)
      |> Map.delete(:encrypted_key)
      |> Map.delete(:secret)
      |> Map.delete(:authorization_date)

    {:noreply, new_state}
  end

  defp schedule_node_renewal(interval) when is_integer(interval) and interval > 0 do
    Process.send_after(__MODULE__, :start_node_renewal, interval * 1000)
  end

  defp next_renewal_offset(interval, trigger_offset) do
    if Utils.time_offset(interval) - trigger_offset <= 0 do
      Process.sleep(Utils.time_offset(interval) * 1000)
      Utils.time_offset(interval) - trigger_offset
    else
      Utils.time_offset(interval) - trigger_offset
    end
  end

  @doc """
  Schedule the application of the renewal of authorized nodes and daily nonce seed at the time of the shared secrets renewal
  """
  @spec schedule_node_renewal_application(list(Crypto.key()), binary(), binary(), DateTime.t()) ::
          :ok
  def schedule_node_renewal_application(
        authorized_nodes,
        encrypted_key,
        secret,
        authorization_date = %DateTime{}
      )
      when is_list(authorized_nodes) and is_binary(encrypted_key) and is_binary(secret) do
    GenServer.call(
      __MODULE__,
      {:schedule_node_renewal_application, authorized_nodes, encrypted_key, secret,
       authorization_date}
    )
  end
end
