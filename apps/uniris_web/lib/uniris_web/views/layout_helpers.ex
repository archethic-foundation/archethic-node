defmodule UnirisWeb.LayoutHelpers do
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

  def format_bytes(nb_bytes) when nb_bytes >= 1024 and nb_bytes < 1048576 do
    "#{Float.round(nb_bytes/1024, 2)} KB"
  end

  def format_bytes(nb_bytes) when nb_bytes >= 1048576 do
    IO.inspect nb_bytes

    "#{Float.round(nb_bytes / 1048576, 2)} MB"
  end

end
