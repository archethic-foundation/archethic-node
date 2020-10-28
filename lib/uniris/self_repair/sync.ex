defmodule Uniris.SelfRepair.Sync do
  @moduledoc false

  alias Uniris.BeaconChain

  alias Uniris.P2P

  alias __MODULE__.SlotConsumer
  alias __MODULE__.SlotFinder

  alias Uniris.Utils

  require Logger

  @doc """
  Return the last synchronization date from the previous cycle of self repair
  """
  @spec last_sync_date() :: DateTime.t()
  def last_sync_date do
    file = last_sync_file()

    if File.exists?(file) do
      file
      |> File.read!()
      |> String.to_integer()
      |> DateTime.from_unix!()
      |> Utils.truncate_datetime()
    else
      :uniris
      |> Application.get_env(__MODULE__)
      |> Keyword.fetch!(:network_startup_date)
    end
  end

  @doc """
  Persist the last sync date
  """
  @spec store_last_sync_date(DateTime.t()) :: :ok
  def store_last_sync_date(date = %DateTime{}) do
    timestamp =
      date
      |> DateTime.to_unix()
      |> Integer.to_string()

    filename = last_sync_file()
    File.mkdir_p(Path.dirname(filename))
    File.write!(filename, timestamp, [:write])

    Logger.info("Last sync date updated: #{DateTime.to_string(date)}")
  end

  defp last_sync_file do
    relative_filepath =
      :uniris
      |> Application.get_env(__MODULE__)
      |> Keyword.get(:last_sync_file, "priv/p2p/last_sync")

    Application.app_dir(:uniris, relative_filepath)
  end

  @doc """
  Retrieve missing transactions from the missing beacon chain slots 
  since the last sync date provided

  Beacon chain pools are retrieved from the given latest synchronization
  date including all the beacon subsets (i.e <<0>>, <<1>>, etc.)

  Once retrieved, the transactions are downloaded and stored if not exists locally
  """
  @spec load_missed_transactions(last_sync_date :: DateTime.t(), patch :: binary()) :: :ok
  def load_missed_transactions(last_sync_date = %DateTime{}, patch) when is_binary(patch) do
    last_sync_date
    |> BeaconChain.get_pools()
    |> Stream.map(fn {subset, nodes} -> {subset, P2P.nearest_nodes(nodes, patch)} end)
    |> SlotFinder.get_beacon_slots(last_sync_date)
    |> SlotConsumer.handle_missing_slots(patch)
  end
end
