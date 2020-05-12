defmodule UnirisCore.Utils do
  @moduledoc false

  @doc """
  Compute an offset of the next shift for a give time interval (in milliseconds)
  """
  @spec time_offset(interval_milliseconds :: non_neg_integer()) ::
          milliseconds :: non_neg_integer()
  def time_offset(interval) when is_integer(interval) and interval > 0 do
    current_time = Time.utc_now().second * 1000
    last_interval = interval * trunc(current_time / interval)
    next_interval = last_interval + interval
    next_interval - current_time
  end

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
    :uniris_core
    |> Application.get_env(process, enabled: true)
    |> Keyword.fetch!(:enabled)
  end

  @doc """
  Truncate a datetime to remove either second or microsecond

  ## Examples

      iex> date = UnirisCore.Utils.truncate_datetime(DateTime.utc_now())
      iex> date.microsecond
      {0, 0}

      iex> date = UnirisCore.Utils.truncate_datetime(DateTime.utc_now(), second?: true, microsecond?: true)
      iex> date.second
      0
      iex> date.microsecond
      {0, 0}

      iex> date = UnirisCore.Utils.truncate_datetime(DateTime.utc_now(), second?: true)
      iex> date.second
      0
  """
  def truncate_datetime(date = %DateTime{}, opts \\ [second?: false, microsecond?: true]) do
    Enum.reduce(opts, date, fn opt, acc ->
      case opt do
        {:second?, true} ->
          %{ acc | second: 0}
        {:microsecond?, true} ->
          %{ acc | microsecond: {0, 0}}
        _ ->
          acc
      end
    end)
  end
end
