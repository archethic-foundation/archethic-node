defmodule UnirisWeb.CodeViewerLive do
  @moduledoc false
  use Phoenix.LiveView

  alias Uniris.Governance.Git

  alias Phoenix.View
  alias UnirisWeb.CodeView

  @root_dir Application.get_env(:uniris, :src_dir)

  def mount(_params, _session, socket) do
    tree =
      "master"
      |> Git.list_branch_files()
      |> build_tree

    {:ok, assign(socket, tree: tree, details: nil)}
  end

  defp build_tree(filelist) do
    Enum.reduce(filelist, %{}, fn filepath, acc ->
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
    {:noreply,
     assign(socket, :details, %{
       filename: filename,
       content: File.read!(Path.join(@root_dir, filename))
     })}
  end
end
