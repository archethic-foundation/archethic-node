defmodule UnirisWeb.ExplorerView do
  @moduledoc false

  use UnirisWeb, :view

  alias Phoenix.Naming

  def roles_to_string(roles) do
    roles
    |> Enum.map(&Atom.to_string/1)
    |> Enum.map(&String.replace(&1, "_", " "))
    |> Enum.join(", ")
  end

  def format_transaction_type(type) do
    formatted_type =
      type
      |> Naming.humanize()
      |> String.upcase()

    content_tag("span", formatted_type, class: "tag is-warning is-light")
  end
end
