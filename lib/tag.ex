defmodule Archethic.Tag do
  @moduledoc """
    Used to tag a module's method
  """
  defmacro __using__(_args) do
    quote do
      @tags %{}
      @on_definition {unquote(__MODULE__), :__on_definition__}
      @before_compile {unquote(__MODULE__), :__before_compile__}
      import Archethic.Tag
      require Archethic.Tag
    end
  end

  # only catch public function tagging
  def __on_definition__(_, :defp, _, _args, _guards, _body), do: :no_op

  def __on_definition__(env, _kinf, name, _args, _guards, _body) do
    tag_method(env.module, name)
  end

  def tag_method(module, method) do
    current_tags = Module.get_attribute(module, :tags)
    tag = Module.get_attribute(module, :tag)

    Module.delete_attribute(module, :tag)

    if !Enum.member?(Map.keys(current_tags), method) do
      update_tags(tag, current_tags, module, method)
    end
  end

  def update_tags(nil, _, _, _), do: :nothing

  def update_tags(tag_list, current_tags, module, method) when is_list(tag_list) do
    method_tags = Map.get(current_tags, method, []) ++ tag_list
    Module.put_attribute(module, :tags, current_tags |> Map.put(method, method_tags))
  end

  def update_tags(tag, current_tags, module, method) do
    method_tags = Map.get(current_tags, method, []) ++ [tag]
    Module.put_attribute(module, :tags, current_tags |> Map.put(method, method_tags))
  end

  defmacro __before_compile__(_env) do
    quote do
      def tags do
        @tags
      end

      def tagged_with?(function_atom, tag) do
        case Map.get(@tags, function_atom) do
          nil -> false
          tags -> Enum.member?(tags, tag)
        end
      end
    end
  end
end
