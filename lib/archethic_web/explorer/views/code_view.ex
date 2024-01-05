defmodule ArchethicWeb.Explorer.CodeView do
  @moduledoc false

  use ArchethicWeb.Explorer, :view

  def render_tree(tree, expanded_folders) when is_map(tree) and is_list(expanded_folders) do
    Enum.reduce(tree, [], &reduce_node(&1, &2, [], expanded_folders))
    |> Enum.reverse()
  end

  defp reduce_node({filename, subfiles}, acc, path, expanded_folders) do
    elem =
      case Map.keys(subfiles) do
        [] ->
          file_node(filename, path)

        _ ->
          folder_node(filename, subfiles, path, expanded_folders)
      end

    [content_tag(:li, elem) | acc]
  end

  defp file_node(filename, path) do
    content_tag(
      :li,
      [
        content_tag(:a, filename,
          "phx-click": "view",
          "phx-value-filename": Path.join(path, filename)
        )
      ]
    )
  end

  defp folder_node(filename, children, path, expanded_folders) do
    children_tags =
      Enum.reduce(children, [], &reduce_node(&1, &2, Path.join(path, filename), expanded_folders))
      |> Enum.reverse()

    visible? = Enum.any?(expanded_folders, &(Path.join(path, filename) == &1))

    class =
      if visible? do
        ""
      else
        "is-hidden"
      end

    action =
      if visible? do
        "collapse"
      else
        "expand"
      end

    content_tag(
      :li,
      [
        content_tag(:a, filename),
        content_tag(
          :ul,
          [
            children_tags
          ],
          class: class
        )
      ],
      "phx-click": action,
      "phx-value-filename": Path.join(path, filename)
    )
  end

  def version_tag(%Version{major: major, minor: minor, patch: patch}) do
    %Version{major: current_major, minor: current_minor, patch: current_patch} = current_version()

    cond do
      major > current_major ->
        content_tag(:span, ["Major"], class: "tag is-danger is-light")

      minor > current_minor ->
        content_tag(:span, ["Minor"], class: "tag is-warning is-light")

      patch > current_patch ->
        content_tag(:span, ["Patch"], class: "tag is-primary is-light")

      true ->
        # happens when version is X.X.X-rcX
        content_tag(:span, ["Patch"], class: "tag is-primary is-light")
    end
  end

  def current_version do
    {:ok, vsn} = :application.get_key(:archethic, :vsn)
    Version.parse!(List.to_string(vsn))
  end

  def format_description(content) do
    {:ok, html, _} = Earmark.as_html(content, gfm: true, breaks: true)
    html
  end
end
