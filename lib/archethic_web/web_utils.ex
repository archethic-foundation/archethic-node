defmodule ArchethicWeb.WebUtils do
  @moduledoc false

  use Phoenix.HTML

  @display_limit 10

  @doc """
   Nb of pages required to display all the transactions.

   ## Examples
      iex> total_pages(45)
      5
      iex> total_pages(40)
      4
      iex> total_pages(1)
      1
      iex> total_pages(10)
      1
      iex> total_pages(11)
      2
      iex> total_pages(0)
      0
  """
  @spec total_pages(tx_count :: non_neg_integer()) ::
          non_neg_integer()
  def total_pages(tx_count) when rem(tx_count, @display_limit) == 0,
    do: count_pages(tx_count)

  def total_pages(tx_count), do: count_pages(tx_count) + 1

  def count_pages(tx_count), do: div(tx_count, @display_limit)

  def keep_remote_ip(conn) do
    %{"remote_ip" => conn.remote_ip}
  end

  def short_address(<<0::8, 0::8, 0::256>>) do
    content_tag(
      "span",
      "0000...0000",
      "data-tooltip": "00000000000000000000000000000000000000000000000000000000000000000000"
    )
  end

  def short_address(address) do
    hex = Base.encode16(address)
    trimmed = String.trim_leading(hex, "0")

    short = String.slice(trimmed, 0..4) <> "..." <> String.slice(trimmed, -4, 4)

    content_tag(
      "span",
      short,
      "data-tooltip": hex
    )
  end

  def format_date(datetime, opts \\ [])

  def format_date(
        %DateTime{
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute,
          second: second
        },
        opts
      ) do
    if Keyword.get(opts, :display_utc, true) do
      "#{year}-#{zero_pad(month)}-#{zero_pad(day)} #{zero_pad(hour)}:#{zero_pad(minute)}:#{zero_pad(second)} UTC"
    else
      "#{year}-#{zero_pad(month)}-#{zero_pad(day)} #{zero_pad(hour)}:#{zero_pad(minute)}:#{zero_pad(second)}"
    end
  end

  def format_date(nil, _opts), do: ""

  def zero_pad(number, amount \\ 2) do
    number
    |> Integer.to_string()
    |> String.pad_leading(amount, "0")
  end

  def format_bytes(nb_bytes) do
    Sizeable.filesize(nb_bytes)
  end

  def from_bigint(int, decimals \\ 8) when is_integer(int) and decimals >= 0 do
    Decimal.div(
      Decimal.new(int),
      Decimal.new(trunc(:math.pow(10, decimals)))
    )
    |> Decimal.to_string()
  end

  def format_usd_amount(uco_amount, uco_price) do
    uco_amount
    |> Decimal.new()
    |> Decimal.div(Decimal.new(100_000_000))
    |> Decimal.mult(Decimal.from_float(uco_price))
    |> Decimal.round(2)
    |> Decimal.to_string()
    |> then(fn usd_price -> "#{usd_price}$" end)
  end

  def format_full_usd_amount(uco_amount, uco_price_at_time, uco_price_now) do
    usd_price_at_time = format_usd_amount(uco_amount, uco_price_at_time)
    usd_price_now = format_usd_amount(uco_amount, uco_price_now)

    "at time: #{usd_price_at_time}, now: #{usd_price_now}"
  end

  @doc """
  Translates an error message.
  """
  def translate_error({msg, opts}) do
    # Because the error messages we show in our forms and APIs
    # are defined inside Ecto, we need to translate them dynamically.
    Enum.reduce(opts, msg, fn
      {key, value}, acc when is_tuple(value) ->
        String.replace(acc, "%{#{key}}", to_string(value |> elem(0)))

      {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
