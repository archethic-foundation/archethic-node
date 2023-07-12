defmodule ArchethicWeb.ErrorView do
  @moduledoc false

  use ArchethicWeb, :explorer_view

  alias Ecto.Changeset
  alias Phoenix.Controller

  # If you want to customize a particular status code
  # for a certain format, you may uncomment below.
  def render("400.json", %{changeset: changeset}) do
    %{status: "invalid", errors: Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def template_not_found(template, _assigns) do
    %{errors: %{detail: Controller.status_message_from_template(template)}}
  end
end
