defmodule ArchEthic.SharedSecrets.NodeRenewalScheduler do
  @moduledoc """
  Schedule the renewal of node shared secrets

  At each `interval - trigger offset` , a new node shared secrets transaction is created with
  the new authorized nodes and is broadcasted to the validation nodes to include
  them as new authorized nodes and update the daily nonce seed.

  A trigger offset is defined to determine the seconds before the interval
  when the transaction will be created and sent.
  (this offset can be tuned by the prediction module to ensure the correctness depending on the latencies)

  For example, for a interval every day (00:00), with 10min offset.
  At 23:58 UTC, an elected node will build and send the transaction for the node renewal shared secrets
  At 00.00 UTC, nodes receives will applied the node shared secrets for the transaction mining
  """

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.DateChecker, as: CronDateChecker
  alias Crontab.Scheduler, as: CronScheduler

  alias ArchEthic

  alias ArchEthic.Crypto

  alias ArchEthic.P2P.Node
  alias ArchEthic.PubSub

  alias ArchEthic.SharedSecrets.NodeRenewal

  alias ArchEthic.Utils

  require Logger

  use GenServer

  @doc """
  Start the node renewal scheduler process without starting the scheduler

  Options:
  - interval: Cron like interval when the node renewal will occur
  - trigger_offset: How many seconds before the interval, the node renewal must be done and sent to all the nodes
  """
  @spec start_link(
          args :: [interval: binary()],
          opts :: Keyword.t()
        ) ::
          {:ok, pid()}
  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @doc false
  def init(opts) do
    interval = Keyword.get(opts, :interval)
    PubSub.register_to_node_update()
    {:ok, %{interval: interval}, :hibernate}
  end

  def handle_info(
        {:node_update, %Node{first_public_key: first_public_key, authorized?: true}},
        state = %{interval: interval}
      ) do
    if Crypto.first_node_public_key() == first_public_key do
      Logger.info("Start node shared secrets scheduling")
      timer = schedule_renewal_message(interval)

      Logger.info(
        "Node shared secrets will be renewed in #{Utils.remaining_seconds_from_timer(timer)}"
      )

      {:noreply, Map.put(state, :timer, timer), :hibernate}
    else
      {:noreply, state, :hibernate}
    end
  end

  def handle_info(
        {:node_update, %Node{first_public_key: first_public_key, authorized?: false}},
        state
      ) do
    with ^first_public_key <- Crypto.first_node_public_key(),
         timer when timer != nil <- Map.get(state, :timer) do
      Process.cancel_timer(timer)
      {:noreply, Map.delete(state, :timer), :hibernate}
    else
      _ ->
        {:noreply, state, :hibernate}
    end
  end

  def handle_info(:make_renewal, state = %{interval: interval}) do
    timer = schedule_renewal_message(interval)

    Logger.info(
      "Node shared secrets will be renewed in #{Utils.remaining_seconds_from_timer(timer)}"
    )

    if NodeRenewal.initiator?() do
      Logger.info("Node shared secrets renewal creation...")
      make_renewal()
    end

    {:noreply, Map.put(state, :timer, timer), :hibernate}
  end

  def handle_cast({:new_conf, conf}, state) do
    case Keyword.get(conf, :interval) do
      nil ->
        {:noreply, state}

      new_interval ->
        {:noreply, Map.put(state, :interval, new_interval)}
    end
  end

  defp make_renewal do
    NodeRenewal.next_authorized_node_public_keys()
    |> NodeRenewal.new_node_shared_secrets_transaction(
      :crypto.strong_rand_bytes(32),
      :crypto.strong_rand_bytes(32)
    )
    |> ArchEthic.send_new_transaction()

    Logger.info(
      "Node shared secrets renewal transaction sent (#{Crypto.number_of_node_shared_secrets_keys()})"
    )
  end

  defp schedule_renewal_message(interval) do
    Process.send_after(self(), :make_renewal, Utils.time_offset(interval) * 1000)
  end

  def config_change(nil), do: :ok

  def config_change(changed_config) do
    GenServer.cast(__MODULE__, {:new_conf, changed_config})
  end

  @doc """
  Get the next shared secrets application date from a given date
  """
  @spec next_application_date(DateTime.t()) :: DateTime.t()
  def next_application_date(date_from = %DateTime{}) do
    if renewal_date?(date_from) do
      get_application_date_interval()
      |> CronParser.parse!(true)
      |> CronScheduler.get_next_run_date!(DateTime.to_naive(date_from))
      |> DateTime.from_naive!("Etc/UTC")
    else
      date_from
    end
  end

  defp renewal_date?(date) do
    get_trigger_interval()
    |> CronParser.parse!(true)
    |> CronDateChecker.matches_date?(DateTime.to_naive(date))
  end

  defp get_trigger_interval do
    Application.get_env(:archethic, __MODULE__) |> Keyword.fetch!(:interval)
  end

  defp get_application_date_interval do
    Application.get_env(:archethic, __MODULE__)
    |> Keyword.fetch!(:application_interval)
  end
end
