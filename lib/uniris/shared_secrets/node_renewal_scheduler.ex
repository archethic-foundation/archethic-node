defmodule Uniris.SharedSecrets.NodeRenewalScheduler do
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

  alias Uniris.Crypto

  alias Uniris.Mining

  alias Uniris.P2P
  alias Uniris.P2P.Message.StartMining

  alias Uniris.SharedSecrets.NodeRenewal

  alias Uniris.Utils

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
    {:ok, %{interval: interval}, {:continue, :start_scheduler}}
  end

  def handle_continue(
        :start_scheduler,
        state = %{interval: interval}
      ) do
    Logger.info("Start node shared secrets scheduler")

    timer = schedule_renewal_message(interval)
    remaining_seconds = remaining_seconds_from_timer(timer)

    Logger.info(
      "Node shared secrets will be renewed in #{HumanizeTime.format_seconds(remaining_seconds)}"
    )

    {:noreply, state}
  end

  def handle_info(:make_renewal, state = %{interval: interval}) do
    timer = schedule_renewal_message(interval)
    remaining_seconds = remaining_seconds_from_timer(timer)

    Logger.info(
      "Node shared secrets will be renewed in #{HumanizeTime.format_seconds(remaining_seconds)}"
    )

    if NodeRenewal.initiator?() do
      Logger.info("Node shared secrets renewal creation...")
      Task.start(&make_renewal/0)
    end

    {:noreply, state}
  end

  defp make_renewal do
    tx =
      NodeRenewal.next_authorized_node_public_keys()
      |> NodeRenewal.new_node_shared_secrets_transaction(
        :crypto.strong_rand_bytes(32),
        :crypto.strong_rand_bytes(32)
      )

    validation_nodes = Mining.transaction_validation_nodes(tx)

    validation_nodes
    |> P2P.broadcast_message(%StartMining{
      transaction: tx,
      validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key),
      welcome_node_public_key: Crypto.node_public_key()
    })
    |> Stream.run()

    Logger.info("Node shared secrets renewal transaction sent")
  end

  defp schedule_renewal_message(interval) do
    Process.send_after(self(), :make_renewal, Utils.time_offset(interval) * 1000)
  end

  defp remaining_seconds_from_timer(timer) do
    case Process.read_timer(timer) do
      false ->
        0

      milliseconds ->
        div(milliseconds, 1000)
    end
  end
end
