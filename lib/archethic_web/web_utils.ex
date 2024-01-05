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

  def short_address(address) do
    hex = Base.encode16(address)
    # we prefix the id because it's forbidden that they start with an integer
    uuid = "_" <> Ecto.UUID.generate()
    uuid2 = "_" <> Ecto.UUID.generate()
    short = String.slice(hex, 0..7) <> "..." <> String.slice(hex, -4, 4)

    content_tag(
      "span",
      [
        # invisible tag that is used for the copy hook
        content_tag("span", hex, id: uuid, style: "display: none"),
        short,
        " ",
        # an anchor to be able to wrap this with an anchor without messing with the copy
        content_tag(
          "a",
          nil,
          class: "copy-icon",
          id: uuid2,
          "phx-hook": "CopyToClipboard",
          "data-target": "##{uuid}"
        )
      ],
      "data-tooltip": hex,
      class: "mono"
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
      content_tag(
        "span",
        "#{year}-#{zero_pad(month)}-#{zero_pad(day)} #{zero_pad(hour)}:#{zero_pad(minute)}:#{zero_pad(second)} UTC",
        class: "mono"
      )
    else
      content_tag(
        "span",
        "#{year}-#{zero_pad(month)}-#{zero_pad(day)} #{zero_pad(hour)}:#{zero_pad(minute)}:#{zero_pad(second)}",
        class: "mono"
      )
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
    |> Decimal.to_string(:normal)
    |> format_number_with_thousand_separator()
  end

  def format_usd_amount(uco_amount, uco_price) do
    uco_amount
    |> Decimal.new()
    |> Decimal.div(Decimal.new(100_000_000))
    |> Decimal.mult(Decimal.from_float(uco_price))
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> format_number_with_thousand_separator()
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

  @doc """
  Format a string that represent a number
  to add thousand separators.
  """
  @spec format_number_with_thousand_separator(String.t()) :: String.t()
  def format_number_with_thousand_separator(str) when is_binary(str) do
    # the algorithm applies only on the integer part
    {int, dec} =
      case String.split(str, ".") do
        [int] -> {int, nil}
        [int, dec] -> {int, dec}
      end

    formatted_int =
      int
      |> String.reverse()
      |> String.codepoints()
      |> Enum.chunk_every(3)
      |> Enum.join(",")
      |> String.reverse()

    if dec == nil do
      formatted_int
    else
      formatted_int <> "." <> dec
    end
  end
end
