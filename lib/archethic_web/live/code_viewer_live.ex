defmodule ArchethicWeb.CodeViewerLive do
  @moduledoc false
  use ArchethicWeb, :live_view

  alias Archethic.Governance
  alias ArchethicWeb.CodeView

  alias Phoenix.View

  # @root_dir Application.compile_env(:archethic, :src_dir)

  def mount(_params, _session, socket) do
    source_files = Governance.list_source_files()
    {:ok, assign(socket, tree: build_tree(source_files), details: nil, expanded_folders: [])}
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
    file_content = Governance.file_content(filename)

    {:noreply,
     assign(socket, :details, %{
       filename: filename,
       content: file_content,
       language: get_language(Path.extname(filename))
     })}
  end

  def handle_event(
        "expand",
        %{"filename" => filename},
        socket = %{assigns: %{expanded_folders: folders}}
      ) do
    folders = folders ++ [filename]
    new_socket = assign(socket, :expanded_folders, folders)
    {:noreply, new_socket}
  end

  def handle_event(
        "collapse",
        %{"filename" => filename},
        socket = %{assigns: %{expanded_folders: folders}}
      ) do
    folders = List.delete(folders, filename)
    new_socket = assign(socket, :expanded_folders, folders)
    {:noreply, new_socket}
  end

  defp get_language(".html"), do: "html"
  defp get_language(".css"), do: "css"
  defp get_language(".js"), do: "javascript"
  defp get_language(".scss"), do: "sass"
  defp get_language(".sh"), do: "bash"
  defp get_language(".md"), do: "markdown"
  defp get_language(".dockerfile"), do: "docker"
  defp get_language(".ex"), do: "elixir"
  defp get_language(".exs"), do: "elixir"
  defp get_language(".eex"), do: "elixir"
  defp get_language(".leex"), do: "elixir"
  defp get_language(".c"), do: "c"
  defp get_language(".erl"), do: "erlang"
  defp get_language(".json"), do: "json"
  defp get_language(_), do: ""
end
