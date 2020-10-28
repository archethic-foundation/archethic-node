defmodule UnirisWeb.CodeViewerLive do
  @moduledoc false
  use Phoenix.LiveView

  alias Uniris.Governance

  alias Phoenix.View
  alias UnirisWeb.CodeView

  @root_dir Application.compile_env(:uniris, :src_dir)

  def mount(_params, _session, socket) do
    source_files = Governance.list_source_files()
    {:ok, assign(socket, tree: build_tree(source_files), details: nil)}
  end

  defp build_tree(file_list) do
    Enum.reduce(file_list, %{}, fn filepath, acc ->
      path =
        filepath
        |> Path.split()
        |> Enum.map(&Access.key(&1, %{}))

      put_in(acc, path, %{})
    end)
  end

  def render(assigns) do
    View.render(CodeView, "viewer.html", assigns)
  end

  def handle_event("view", %{"filename" => filename}, socket) do
    file_content = File.read!(Path.join(@root_dir, filename))

    {:noreply,
     assign(socket, :details, %{
       filename: filename,
       content: file_content
     })}
  end
end
