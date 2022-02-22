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

  def to_float(number) when is_number(number) do
    :erlang.float_to_binary(number / 100_000_000, [:compact, decimals: 8])
  end

  def format_usd_amount(uco_amount, uco_price) do
    usd_price =
      (uco_price * uco_amount)
      |> to_float()
      |> Float.parse()
      |> elem(0)
      |> Float.round(2)
      |> :erlang.float_to_binary(decimals: 2)

    "#{usd_price}$"
  end

  def format_full_usd_amount(uco_amount, uco_price_at_time, uco_price_now) do
    usd_price_at_time = format_usd_amount(uco_amount, uco_price_at_time)
    usd_price_now = format_usd_amount(uco_amount, uco_price_now)

    "at time: #{usd_price_at_time}, now: #{usd_price_now}"
  end
end
