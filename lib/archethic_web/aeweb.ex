defmodule ArchethicWeb.AEWeb do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller, namespace: ArchethicWeb.AEWeb

      import Plug.Conn
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/archethic_web/aeweb/templates",
        namespace: ArchethicWeb.AEWeb

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_flash: 1, get_flash: 2, view_module: 1]
      import ArchethicWeb.WebUtils
      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Phoenix.Controller
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
