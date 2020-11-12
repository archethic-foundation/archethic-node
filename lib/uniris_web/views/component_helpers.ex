defmodule UnirisWeb.ComponentHelpers do
  @moduledoc false

  alias UnirisWeb.ComponentView

  def component(template, assigns \\ []) do
    ComponentView.render(template, assigns)
  end
end
