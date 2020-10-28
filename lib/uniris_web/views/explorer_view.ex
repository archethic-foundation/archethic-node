defmodule UnirisWeb.ExplorerView do
  @moduledoc false

  use UnirisWeb, :view

  def roles_to_string(roles) do
    roles
    |> Enum.map(&Atom.to_string/1)
    |> Enum.map(&String.replace(&1, "_", " "))
    |> Enum.join(", ")
  end
end
