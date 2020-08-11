defmodule Uniris.Utils do
  @moduledoc false

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  @doc """
  Compute an offset of the next shift in seconds for a given time interval 
  (ie. "* * * * * *" for every minute)
  """
  @spec time_offset(cron_interval :: binary()) :: seconds :: non_neg_integer()
  def time_offset(interval) do
    next_slot =
      interval
      |> CronParser.parse!()
      |> CronScheduler.get_next_run_date!()
      |> DateTime.from_naive!("Etc/UTC")

    DateTime.diff(next_slot, DateTime.utc_now(), :second)
  end

  @doc """
  Configure supervisor children to be disabled if their configuration has a `enabled` option to false
  """
  @spec configurable_children(list({process :: atom(), args :: list(), opts :: list()})) ::
          list(Supervisor.child_spec())
  def configurable_children(children) do
    Enum.map(children, fn {process, args, opts} ->
      if should_start?(process) do
        Supervisor.child_spec({process, args}, opts)
      else
        []
      end
    end)
    |> List.flatten()
  end

  defp should_start?(process) do
    case Application.get_env(:uniris, process) do
      nil ->
        true

      conf ->
        Keyword.get(conf, :enabled, true)
    end
  end

  @doc """
  Truncate a datetime to remove either second or microsecond

  ## Examples

      iex> date = Uniris.Utils.truncate_datetime(DateTime.utc_now())
      iex> date.microsecond
      {0, 0}

      iex> date = Uniris.Utils.truncate_datetime(DateTime.utc_now(), second?: true, microsecond?: true)
      iex> date.second
      0
      iex> date.microsecond
      {0, 0}

      iex> date = Uniris.Utils.truncate_datetime(DateTime.utc_now(), second?: true)
      iex> date.second
      0
  """
  def truncate_datetime(date = %DateTime{}, opts \\ [second?: false, microsecond?: true]) do
    Enum.reduce(opts, date, fn opt, acc ->
      case opt do
        {:second?, true} ->
          %{acc | second: 0}

        {:microsecond?, true} ->
          %{acc | microsecond: {0, 0}}

        _ ->
          acc
      end
    end)
  end
end
