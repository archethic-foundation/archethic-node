defmodule ArchethicWeb.API.Types.RecipientArgType do
  @moduledoc false

  use Ecto.Type

  def type, do: :any

  # Handle casting from external input (e.g., from forms or APIs)
  def cast(value) when is_map(value) do
    {:ok, value}
  end

  def cast(value) when is_list(value) do
    {:ok, value}
  end

  def cast(_), do: :error

  def load(data) do
    {:ok, data}
  end

  def dump(data) when is_map(data) do
    {:ok, data}
  end

  def dump(data) when is_list(data) do
    {:ok, data}
  end

  def dump(_), do: :error
end
