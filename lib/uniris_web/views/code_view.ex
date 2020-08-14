defmodule UnirisWeb.CodeView do
  @moduledoc false

  use UnirisWeb, :view

  def render_tree(tree) when is_map(tree) do
    Enum.reduce(tree, [], &reduce_node(&1, &2, []))
    |> Enum.reverse()
  end

  defp reduce_node({filename, subfiles}, acc, path) do
    elem =
      case Map.keys(subfiles) do
        [] ->
          file_node(filename, path)

        _ ->
          folder_node(filename, subfiles, path)
      end

    [content_tag(:div, elem, class: "row") | acc]
  end

  defp file_node(filename, path) do
    content_tag(:div, filename,
      class: "column code_viewer_file",
      "phx-click": "view",
      "phx-value-filename": Path.join(path, filename)
    )
  end

  defp folder_node(filename, children, path) do
    children_tags =
      Enum.reduce(children, [], &reduce_node(&1, &2, Path.join(path, filename)))
      |> Enum.reverse()

    content_tag(
      :div,
      [
        content_tag(
          :div,
          [
            content_tag(:div, filename, class: "column")
          ],
          class: "row"
        ),
        content_tag(
          :div,
          [
            content_tag(:div, children_tags, class: "column code_viewer_subdir")
          ],
          class: "row"
        )
      ],
      class: "column"
    )
  end
end
