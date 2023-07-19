defmodule Archethic.Contracts.Interpreter.CommonInterpreter do
  @moduledoc """
  The prewalk and postwalk functions receive an `acc` for convenience.
  They should see it as an opaque variable and just forward it.

  This way we can use this interpreter inside other interpreters, and each deal with the acc how they want to.
  """

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Scope

  @modules_whitelisted Library.list_common_modules()

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
  def prewalk(node = {:!=, _, _}, acc), do: {node, acc}
  def prewalk(node = {:++, _, _}, acc), do: {node, acc}
  def prewalk(node = {:!, _, _}, acc), do: {node, acc}
  def prewalk(node = {:&&, _, _}, acc), do: {node, acc}
  def prewalk(node = {:||, _, _}, acc), do: {node, acc}

  # ranges
  def prewalk(node = {:.., _, _}, acc), do: {node, acc}

  # enter block == new scope
  def prewalk(
        _node = {:__block__, meta, expressions},
        acc
      ) do
    # create a "ref" for each block
    # references are not AST valid, so we convert them to binary
    # (ps: charlist is a slow alternative because the Macro.traverse will step into every character)
    ref = :erlang.list_to_binary(:erlang.ref_to_list(make_ref()))
    new_acc = acc ++ [ref]

    # create the child scope in parent scope
    create_scope_ast =
      quote do
        Scope.create(unquote(new_acc))
      end

    {
      {:__block__, meta, [create_scope_ast | expressions]},
      new_acc
    }
  end

  # blocks
  def prewalk(node = {:do, _}, acc), do: {node, acc}
  def prewalk(node = :do, acc), do: {node, acc}

  # literals
  # it is fine allowing atoms since the users can't create them (this avoid whitelisting functions/modules we use in the prewalk)
  def prewalk(node, acc) when is_atom(node), do: {node, acc}
  def prewalk(node, acc) when is_boolean(node), do: {node, acc}
  def prewalk(node, acc) when is_number(node), do: {node, acc}
  def prewalk(node, acc) when is_binary(node), do: {node, acc}

  # converts all keywords to maps
  def prewalk(node, acc) when is_list(node) do
    if AST.is_keyword_list?(node) do
      new_node = AST.keyword_to_map(node)
      {new_node, acc}
    else
      {node, acc}
    end
  end

  # pairs (used in maps)
  def prewalk(node = {key, _}, acc) when is_binary(key), do: {node, acc}

  # maps (required because we create maps for each scope in the ActionInterpreter's prewalk)
  def prewalk(node = {:%{}, _, _}, acc), do: {node, acc}

  # variables
  def prewalk(node = {{:atom, var_name}, _, nil}, acc) when is_binary(var_name), do: {node, acc}
  def prewalk(node = {:atom, var_name}, acc) when is_binary(var_name), do: {node, acc}

  # module call
  def prewalk(node = {{:., _, [{:__aliases__, _, _}, _]}, _, _}, acc), do: {node, acc}
  def prewalk(node = {:., _, [{:__aliases__, _, _}, _]}, acc), do: {node, acc}

  # function call
  def prewalk(node = {{:atom, _}, _, args}, acc) when is_list(args), do: {node, acc}

  # whitelisted modules
  def prewalk(node = {:__aliases__, _, [atom: module_name]}, acc)
      when module_name in @modules_whitelisted,
      do: {node, acc}

  # internal modules (Process/Scope/Kernel)
  def prewalk(node = {:__aliases__, _, [atom]}, acc) when is_atom(atom), do: {node, acc}

  # internal functions
  def prewalk(node = {:put_in, _, _}, acc), do: {node, acc}
  def prewalk(node = {:get_in, _, _}, acc), do: {node, acc}
  def prewalk(node = {:update_in, _, _}, acc), do: {node, acc}

  # if
  def prewalk(_node = {:if, meta, [predicate, do_else_keyword]}, acc) do
    # wrap the do/else blocks
    do_else_keyword =
      Enum.map(do_else_keyword, fn {key, value} ->
        {key, AST.wrap_in_block(value)}
      end)

    new_node = {:if, meta, [predicate, do_else_keyword]}
    {new_node, acc}
  end

  # else (no wrap needed since it's done in the if)
  def prewalk(node = {:else, _}, acc), do: {node, acc}
  def prewalk(node = :else, acc), do: {node, acc}

  # string interpolation
  def prewalk(node = {{:., _, [Kernel, :to_string]}, _, _}, acc), do: {node, acc}
  def prewalk(node = {:., _, [Kernel, :to_string]}, acc), do: {node, acc}
  def prewalk(node = {:binary, _, nil}, acc), do: {node, acc}
  def prewalk(node = {:<<>>, _, _}, acc), do: {node, acc}
  def prewalk(node = {:"::", _, [{{:., _, [Kernel, :to_string]}, _, _}, _]}, acc), do: {node, acc}

  # forbid "if" as an expression
  def prewalk(
        node = {:=, _, [_, {:if, _, _}]},
        _acc
      ) do
    throw({:error, node, "Forbidden to use if as an expression."})
  end

  # forbid "for" as an expression
  def prewalk(
        node =
          {:=, _,
           [
             {{:atom, _}, _, nil},
             {{:atom, "for"}, _, _}
           ]},
        _acc
      ) do
    throw({:error, node, "Forbidden to use for as an expression."})
  end

  # whitelist assignation & write them to scope
  # this is done in the prewalk because it must be done before the "variable are read from scope" step
  def prewalk(
        _node = {:=, _, [{{:atom, var_name}, _, nil}, value]},
        acc
      ) do
    new_node =
      quote do
        Scope.write_cascade(unquote(acc), unquote(var_name), unquote(value))
      end

    {
      new_node,
      acc
    }
  end

  # Dot access non-nested (x.y)
  def prewalk(_node = {{:., _, [{{:atom, map_name}, _, nil}, {:atom, key_name}]}, _, _}, acc) do
    new_node =
      quote do
        Scope.read(unquote(acc), unquote(map_name), unquote(key_name))
      end

    {new_node, acc}
  end

  # Dot access nested (x.y.z)
  def prewalk({{:., _, [first_arg = {{:., _, _}, _, _}, {:atom, key_name}]}, _, []}, acc) do
    {nested, new_acc} = prewalk(first_arg, acc)

    new_node =
      quote do
        get_in(unquote(nested), [unquote(key_name)])
      end

    {new_node, new_acc}
  end

  # Map access non-nested (x[y])
  def prewalk(
        _node = {{:., _, [Access, :get]}, _, [{{:atom, map_name}, _, nil}, accessor]},
        acc
      ) do
    # accessor can be a variable, a function call, a dot access, a string
    new_node =
      quote do
        Scope.read(unquote(acc), unquote(map_name), unquote(accessor))
      end

    {new_node, acc}
  end

  # Map access nested (x[y][z])
  def prewalk(
        _node = {{:., _, [Access, :get]}, _, [first_arg = {{:., _, _}, _, _}, accessor]},
        acc
      ) do
    {nested, new_acc} = prewalk(first_arg, acc)

    new_node =
      quote do
        get_in(unquote(nested), [unquote(accessor)])
      end

    {new_node, new_acc}
  end

  # for var in list
  def prewalk(
        _node =
          {{:atom, "for"}, meta,
           [
             {:in, _,
              [
                {{:atom, var_name}, _, nil},
                list
              ]},
             [do: block]
           ]},
        acc
      ) do
    ast =
      {{:atom, "for"}, meta,
       [
         # we change the "var in list" to "var: list" (which will be automatically converted to %{var => list})
         # to avoid the "var" interpreted as a variable (which would have been converted to get_in/2)
         [{{:atom, var_name}, list}],
         # wrap in a block to be able to pattern match it to create a scope
         [do: AST.wrap_in_block(block)]
       ]}

    {ast, acc}
  end

  # log (not documented, only useful for developer debugging)
  # will soon be updated to log into the playground console
  def prewalk(_node = {{:atom, "log"}, _, [data]}, acc) do
    new_node = quote do: apply(IO, :inspect, [unquote(data)])
    {new_node, acc}
  end

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
  # exit block == set parent scope
  def postwalk(_, _, function_keys \\ [])

  def postwalk(
        node = {:__block__, _, _},
        acc,
        _
      ) do
    {node, List.delete_at(acc, -1)}
  end

  # common modules call
  def postwalk(
        node =
          {{:., meta, [{:__aliases__, _, [atom: module_name]}, {:atom, function_name}]}, _, args},
        acc,
        _
      )
      when module_name in @modules_whitelisted do
    absolute_module_atom =
      Code.ensure_loaded!(
        String.to_existing_atom(
          "Elixir.Archethic.Contracts.Interpreter.Library.Common.#{module_name}"
        )
      )

    # check function exists
    unless Library.function_exists?(absolute_module_atom, function_name) do
      throw({:error, node, "unknown function"})
    end

    # check function is available with given arity
    unless Library.function_exists?(absolute_module_atom, function_name, length(args)) do
      throw({:error, node, "invalid function arity"})
    end

    module_atom = String.to_existing_atom(module_name)
    function_atom = String.to_existing_atom(function_name)

    # check the type of the args
    unless absolute_module_atom.check_types(function_atom, args) do
      throw({:error, node, "invalid function arguments"})
    end

    meta_with_alias = Keyword.put(meta, :alias, absolute_module_atom)

    new_node =
      {{:., meta, [{:__aliases__, meta_with_alias, [module_atom]}, function_atom]}, meta, args}

    {new_node, acc}
  end

  # variable are read from scope
  def postwalk(
        _node = {{:atom, var_name}, _, nil},
        acc,
        _
      ) do

    new_node =
      quote do
        Scope.read(unquote(acc), unquote(var_name))
      end

    {new_node, acc}
  end

  def postwalk(node = {{:atom, function_name}, _, args}, acc, function_keys) when is_list(args) do
    function_key = function_name <> "/" <> Integer.to_string(length(args))

    case Enum.member?(function_keys, function_key) do
      true ->
        new_node =
          quote do
            Scope.get_function_ast(unquote(function_name), unquote(args))
            |> Code.eval_quoted()
          end

        {new_node, acc}

      false ->
        throw({:error, node, "The function " <> function_key <> " does not exist"})
    end
  end

  # for var in list
  def postwalk(
        _node =
          {{:atom, "for"}, _,
           [
             {:%{}, _, [{var_name, list}]},
             [do: block]
           ]},
        acc,
        _
      ) do
    # FIXME: here acc is already the parent acc, it is not the acc of the do block
    # FIXME: this means that our `var_name` will live in the parent scope
    # FIXME: it works (since we can read from parent) but it will override the parent binding if there's one

    # transform the for-loop into Enum.each
    # and create a variable in the scope
    new_node =
      quote do
        Enum.each(unquote(list), fn x ->
          Scope.write_at(unquote(acc), unquote(var_name), x)

          unquote(block)
        end)
      end

    {new_node, acc}
  end

  # BigInt mathematics to avoid floating point issues
  def postwalk(_node = {ast, meta, [lhs, rhs]}, acc, _) when ast in [:*, :/, :+, :-] do
    new_node =
      quote line: Keyword.fetch!(meta, :line) do
        AST.decimal_arithmetic(unquote(ast), unquote(lhs), unquote(rhs))
      end

    {new_node, acc}
  end

  # whitelist rest
  def postwalk(node, acc, _), do: {node, acc}

  # ----------------------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  # ----------------------------------------------------------------------
end
