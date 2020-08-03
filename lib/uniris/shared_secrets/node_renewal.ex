defmodule Uniris.SharedSecrets.NodeRenewal do
  @moduledoc false

  alias Uniris.Crypto

  alias Uniris.Election
  alias Uniris.Election.ValidationConstraints

  alias Uniris.P2P
  alias Uniris.P2P.Message.StartMining
  alias Uniris.P2P.Node

  alias Uniris.SharedSecrets
  alias Uniris.TaskSupervisor
  alias Uniris.Utils

  use GenServer

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(interval: interval, trigger_offset: trigger_offset) do
    schedule_renewal(Utils.time_offset(interval - trigger_offset))
    {:ok, %{interval: interval, trigger_offset: trigger_offset}}
  end

  def handle_info(:renew, state = %{interval: interval, trigger_offset: trigger_offset}) do
    authorized_node_public_keys =
      P2P.list_nodes()
      |> Enum.filter(&(&1.ready? && &1.available? && &1.authorized?))
      |> Enum.map(& &1.last_public_key)

    if Crypto.node_public_key() in authorized_node_public_keys do
      do_renewal()
      schedule_renewal(interval - trigger_offset)
      {:noreply, state}
    else
      schedule_renewal(interval - trigger_offset)
      {:noreply, state}
    end
  end

  defp do_renewal do
    tx =
      SharedSecrets.new_node_shared_secrets_transaction(
        authorized_nodes(),
        :crypto.strong_rand_bytes(32),
        :crypto.strong_rand_bytes(32)
      )

    # Determine if the current node is in charge to the send the new transaction
    authorized_storage_nodes =
      Enum.filter(P2P.list_nodes(), &(&1.ready? && &1.available? && &1.authorized?))

    [%Node{last_public_key: key} | _] =
      Election.storage_nodes(tx.address, authorized_storage_nodes)

    if key == Crypto.node_public_key() do
      Logger.info("Node shared secret key renewal")

      validation_nodes =
        tx
        |> Election.validation_nodes()
        |> Enum.map(& &1.last_public_key)

      TaskSupervisor
      |> Task.Supervisor.async_stream_nolink(validation_nodes, fn node ->
        P2P.send_message(node, %StartMining{
          transaction: tx,
          welcome_node_public_key: Crypto.node_public_key(),
          validation_node_public_keys: validation_nodes
        })
      end)
      |> Stream.run()
    end
  end

  # Find out the next authorized nodes based on the previous ones and the heuristic validation constraints
  # to embark new validation nodes in the network
  defp authorized_nodes do
    authorized_nodes = Enum.filter(P2P.list_nodes(), & &1.authorized?)

    %ValidationConstraints{
      min_validation_number: min_validation_number,
      min_geo_patch: min_geo_patch
    } = Election.validation_constraints()

    (Enum.filter(P2P.list_nodes(), & &1.ready?) -- authorized_nodes)
    |> select_new_authorized_nodes(min_validation_number, min_geo_patch.(), authorized_nodes)
    |> Enum.map(& &1.last_public_key)
  end

  # Using the minimum number of validation and minimum geographical distribution
  # A selection is perfomed to add new validation nodes based on those constraints
  defp select_new_authorized_nodes([node | rest], min_validation_number, min_geo_patch, acc) do
    distinct_geo_patches =
      acc
      |> Enum.map(& &1.geo_patch)
      |> Enum.uniq()

    if length(acc) < min_validation_number and length(distinct_geo_patches) < min_geo_patch do
      select_new_authorized_nodes(rest, min_validation_number, min_geo_patch, acc ++ [node])
    else
      acc
    end
  end

  defp select_new_authorized_nodes([], _, _, acc), do: acc

  defp schedule_renewal(0), do: :ok

  defp schedule_renewal(interval) when is_integer(interval) and interval > 0 do
    Process.send_after(self(), :renew, interval)
  end
end
