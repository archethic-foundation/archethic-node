defmodule ArchethicWeb.DirListingView do
  @moduledoc false
  use ArchethicWeb, :view

  def datetime_to_str(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
  end
end
