defmodule Archethic.Contracts.Interpreter.Version1.CommonInterpreter do
  @moduledoc """
  The prewalk and postwalk functions receive an `acc` for convenience.
  They should see it as an opaque variable and just forward it.

  This way we can use this interpreter inside other interpreters, and each deal with the acc how they want to.
  """

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  @modules_whitelisted ["Map", "List"]

  # ----------------------------------------------------------------------
  #                                _ _
  #   _ __  _ __ _____      ____ _| | | __
  #  | '_ \| '__/ _ \ \ /\ / / _` | | |/ /
  #  | |_) | | |  __/\ V  V | (_| | |   <
  #  | .__/|_|  \___| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------
  # the atom marker (set by sanitize_code)
  def prewalk(:atom, acc), do: {:atom, acc}

  # expressions
  def prewalk(node = {:+, _, _}, acc), do: {node, acc}
  def prewalk(node = {:-, _, _}, acc), do: {node, acc}
  def prewalk(node = {:/, _, _}, acc), do: {node, acc}
  def prewalk(node = {:*, _, _}, acc), do: {node, acc}
  def prewalk(node = {:>, _, _}, acc), do: {node, acc}
  def prewalk(node = {:<, _, _}, acc), do: {node, acc}
  def prewalk(node = {:>=, _, _}, acc), do: {node, acc}
  def prewalk(node = {:<=, _, _}, acc), do: {node, acc}
  def prewalk(node = {:|>, _, _}, acc), do: {node, acc}
  def prewalk(node = {:==, _, _}, acc), do: {node, acc}

  # blocks
  def prewalk(node = {:__block__, _, _}, acc), do: {node, acc}
  def prewalk(node = {:do, _}, acc), do: {node, acc}
  def prewalk(node = :do, acc), do: {node, acc}

  # primitives
  def prewalk(node, acc) when is_boolean(node), do: {node, acc}
  def prewalk(node, acc) when is_number(node), do: {node, acc}
  def prewalk(node, acc) when is_binary(node), do: {node, acc}

  # converts all keywords to maps
  def prewalk(node, acc) when is_list(node) do
    if AST.is_keyword_list?(node) do
      new_node = AST.keyword_to_map(node)
      IO.inspect(node, label: "node")
      IO.inspect(new_node, label: "new_node")
      {new_node, acc}
    else
      {node, acc}
    end
  end

  # pairs (used in maps)
  def prewalk(node = {key, _}, acc) when is_binary(key), do: {node, acc}

  # variables
  def prewalk(node = {{:atom, varName}, _, nil}, acc) when is_binary(varName), do: {node, acc}
  def prewalk(node = {:atom, varName}, acc) when is_binary(varName), do: {node, acc}

  # dot access (x.y)
  def prewalk(
        _node = {{:., _, [{{:atom, mapName}, _, nil}, {:atom, keyName}]}, _, _},
        acc
      ) do
    # shoud also work: get_in(scope, [unquote(mapName), unquote(keyName)])
    new_node =
      quote context: SmartContract do
        get_in(get_in(scope, [unquote(mapName)]), [unquote(keyName)])
      end

    {new_node, acc}
  end

  # module call
  def prewalk(node = {{:., _, [{:__aliases__, _, _}, _]}, _, _}, acc), do: {node, acc}
  def prewalk(node = {:., _, [{:__aliases__, _, _}, _]}, acc), do: {node, acc}

  def prewalk(node = {:__aliases__, _, [atom: moduleName]}, acc)
      when moduleName in @modules_whitelisted,
      do: {node, acc}

  # scope assignation (because assignations are done in the ActionInterpreter's prewalk)
  def prewalk(node = {:scope, _, SmartContract}, acc), do: {node, acc}
  def prewalk(node = {:put_in, _, [{:scope, [], SmartContract} | _]}, acc), do: {node, acc}

  # dot access (because dot access is done in the CommonInterpreter's prewalk)
  def prewalk(node = {:get_in, _, [{:scope, [], SmartContract} | _]}, acc), do: {node, acc}

  # blacklist rest
  def prewalk(node, _acc), do: throw({:error, node, "unexpected term"})

  # ----------------------------------------------------------------------
  #                   _                 _ _
  #   _ __   ___  ___| |___      ____ _| | | __
  #  | '_ \ / _ \/ __| __\ \ /\ / / _` | | |/ /
  #  | |_) | (_) \__ | |_ \ V  V | (_| | |   <
  #  | .__/ \___/|___/\__| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------
  def postwalk(
        _node =
          {{:., meta, [{:__aliases__, _, [atom: moduleName]}, {:atom, functionName}]}, _, args},
        acc
      )
      when moduleName in @modules_whitelisted do
    aliasAtom =
      String.to_existing_atom(
        "Elixir.Archethic.Contracts.Interpreter.Version1.Library.Common.#{moduleName}"
      )

    # ensure module is loaded (so the atoms corresponding to the functions exist)
    Code.ensure_loaded!(aliasAtom)

    moduleAtom = String.to_existing_atom(moduleName)
    functionAtom = String.to_existing_atom(functionName)
    meta_with_alias = Keyword.put(meta, :alias, aliasAtom)

    new_node =
      {{:., meta, [{:__aliases__, meta_with_alias, [moduleAtom]}, functionAtom]}, meta, args}

    {new_node, acc}
  end

  # whitelist rest
  def postwalk(node, acc), do: {node, acc}

  # ----------------------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  # ----------------------------------------------------------------------
end
