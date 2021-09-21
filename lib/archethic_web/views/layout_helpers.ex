defmodule ArchEthicWeb.LayoutHelpers do
  @moduledoc false

  def format_date(%DateTime{
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second
      }) do
    "#{year}/#{zero_pad(month)}/#{zero_pad(day)} #{zero_pad(hour)}:#{zero_pad(minute)}:#{zero_pad(second)} UTC"
  end

  def format_date(nil), do: ""

  def zero_pad(number, amount \\ 2) do
    number
    |> Integer.to_string()
    |> String.pad_leading(amount, "0")
  end

  def format_bytes(nb_bytes) do
    Sizeable.filesize(nb_bytes)
  end

  def format_seconds(seconds) do
    HumanizeTime.format_seconds(seconds)
  end

  def format_float(float) when is_float(float) do
    :erlang.float_to_binary(float, [:compact, decimals: 8])
  end
end
