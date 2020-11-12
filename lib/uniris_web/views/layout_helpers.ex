defmodule UnirisWeb.LayoutHelpers do
  @moduledoc false
  def format_date(%DateTime{
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second
      }) do
    "#{year}/#{zero_pad(month)}/#{zero_pad(day)} #{zero_pad(hour)}:#{zero_pad(minute)}:#{
      zero_pad(second)
    }"
  end

  def format_date(nil), do: ""

  def zero_pad(number, amount \\ 2) do
    number
    |> Integer.to_string()
    |> String.pad_leading(amount, "0")
  end

  def format_bytes(nb_bytes) when nb_bytes < 1024 do
    "#{nb_bytes} B"
  end

  def format_bytes(nb_bytes) when nb_bytes >= 1024 and nb_bytes < 1_048_576 do
    "#{Float.round(nb_bytes / 1024, 2)} KB"
  end

  def format_bytes(nb_bytes) when nb_bytes >= 1_048_576 do
    "#{Float.round(nb_bytes / 1_048_576, 2)} MB"
  end

  def format_transaction_type(:node), do: "NODE"
  def format_transaction_type(:node_shared_secrets), do: "NODE_SECRETS"
  def format_transaction_type(:transfer), do: "TRANSF"
  def format_transaction_type(:code_proposal), do: "CODE_PROP"
  def format_transaction_type(:code_approval), do: "CODE_APPR"
  def format_transaction_type(:hosting), do: "HOSTING"
  def format_transaction_type(:id), do: "ID"
  def format_transaction_type(:keychain), do: "KEYCHAIN"

  def format_seconds(0), do: "0s"

  def format_seconds(seconds) do
    initial_acc = %{
      days: 0,
      hours: 0,
      minutes: 0,
      seconds: 0
    }

    initial_acc
    |> calculate_times(abs(seconds))
    |> print_duration()
  end

  defp calculate_times(time_tracker, 0), do: time_tracker

  defp calculate_times(time_tracker, seconds) do
    day_seconds = 86_400
    hour_seconds = 3_600
    minute_seconds = 60

    cond do
      seconds / day_seconds >= 1 ->
        days = time_tracker.days + div(seconds, day_seconds)
        remaining_seconds = seconds - days * day_seconds
        calculate_times(%{time_tracker | days: days}, remaining_seconds)

      seconds / hour_seconds >= 1 ->
        hours = time_tracker.hours + div(seconds, hour_seconds)
        remaining_seconds = seconds - hours * hour_seconds
        calculate_times(%{time_tracker | hours: hours}, remaining_seconds)

      seconds / minute_seconds >= 1 ->
        minutes = time_tracker.minutes + div(seconds, minute_seconds)
        remaining_seconds = seconds - minutes * minute_seconds
        calculate_times(%{time_tracker | minutes: minutes}, remaining_seconds)

      true ->
        %{time_tracker | seconds: seconds}
    end
  end

  defp print_duration(duration) do
    %{days: days, hours: hours, minutes: minutes, seconds: seconds} = duration

    default_formatter = default_formatters()

    days_f = default_formatter[:days]
    hours_f = default_formatter[:hours]
    minutes_f = default_formatter[:minutes]
    seconds_f = default_formatter[:seconds]

    cond do
      days > 0 ->
        day_string = days_f.(days)

        rounded_hours =
          if minutes >= 30 do
            hours + 1
          else
            hours
          end

        hour_string = hours_f.(rounded_hours)
        String.trim("#{day_string} #{hour_string}")

      hours > 0 ->
        hour_string = hours_f.(hours)

        rounded_mins =
          if seconds >= 30 do
            minutes + 1
          else
            minutes
          end

        minute_string = minutes_f.(rounded_mins)
        String.trim("#{hour_string} #{minute_string}")

      minutes > 0 ->
        minute_string = minutes_f.(minutes)
        seconds_string = seconds_f.(seconds)
        String.trim("#{minute_string} #{seconds_string}")

      true ->
        String.trim(seconds_f.(seconds))
    end
  end

  defp print_days(0), do: ""
  defp print_days(1), do: "1 day"
  defp print_days(duration), do: "#{duration} days"

  defp print_hours(0), do: ""
  defp print_hours(duration), do: "#{duration} hr"

  defp print_minutes(0), do: ""
  defp print_minutes(duration), do: "#{duration} min"

  defp print_seconds(0), do: ""
  defp print_seconds(duration), do: "#{duration} sec"

  defp default_formatters do
    %{
      days: fn day -> print_days(day) end,
      hours: fn hour -> print_hours(hour) end,
      minutes: fn minute -> print_minutes(minute) end,
      seconds: fn second -> print_seconds(second) end
    }
  end
end
