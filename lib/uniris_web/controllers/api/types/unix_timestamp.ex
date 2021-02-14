defmodule UnirisWeb.API.Types.UnixTimestamp do
  @moduledoc false

  use Ecto.Type

  def type, do: :integer

  def cast(timestamp) when is_integer(timestamp) do
    with true <- length(Integer.digits(timestamp)) == 13,
         {:ok, datetime} <- DateTime.from_unix(timestamp, :millisecond) do
      {:ok, datetime}
    else
      _ ->
        {:error, [message: "invalid unix timestamp"]}
    end
  end

  def cast(_), do: {:error, [message: "must be an integer"]}

  def load(timestamp), do: timestamp

  def dump(timestamp = %DateTime{}), do: DateTime.to_unix(timestamp, :millisecond)
  def dump(_), do: :error
end
