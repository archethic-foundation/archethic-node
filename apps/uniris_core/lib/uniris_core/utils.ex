defmodule UnirisCore.Utils do
  @moduledoc false

  @doc """
  Compute an offset of the next shift for a give time interval (in seconds)
  """
  @spec time_offset(interval_seconds :: non_neg_integer()) :: non_neg_integer()
  def time_offset(interval) when is_integer(interval) and interval > 0 do
    current_time = Time.utc_now().second
    last_interval = interval * trunc(current_time / interval)
    next_interval = last_interval + interval
    next_interval - current_time
  end
end
