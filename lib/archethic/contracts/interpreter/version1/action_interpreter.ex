defmodule Archethic.Contracts.Interpreter.Version1.ActionInterpreter do
  @moduledoc false
  @modules_whitelisted ["Contract"]

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Version1.CommonInterpreter
  alias Archethic.Contracts.Interpreter.Version1.Library
  alias Archethic.Contracts.Interpreter.Version1.Scope

  @doc """
  Parse the given node and return the trigger and the actions block.
  """
  @spec parse(any()) :: {:ok, atom(), any()} | {:error, any(), String.t()}
  def parse({{:atom, "actions"}, _, [keyword, [do: block]]}) do
    trigger_type = extract_trigger(keyword)

    # We only parse the do..end block with the macro.traverse
    # this help us keep a clean accumulator that is used only for scoping.
    actions_ast = parse_block(AST.wrap_in_block(block))

    {:ok, trigger_type, actions_ast}
  catch
    {:error, node} ->
      {:error, node, "unexpected term"}

    {:error, node, reason} ->
      {:error, node, reason}
  end

  def parse(node) do
    {:error, node, "unexpected term"}
  end

  @doc """
  Execute actions code and returns either the next transaction or nil
  """
  @spec execute(any(), map()) :: Transaction.t() | nil
  def execute(ast, constants \\ %{}) do
    :ok = Macro.validate(ast)

    # initiate a transaction that will be use by the "Contract" module
    next_tx = %Transaction{data: %TransactionData{}}

    # we use the process dictionary to store our scope
    # because it is mutable.
    #
    # constants should already contains the "magic" variables
    #   - "contract": current contract transaction
    #   - "transaction": the incoming transaction (when trigger=transaction)
    Process.put(
      :scope,
      Map.put(constants, "next_transaction", next_tx)
    )

    # we can ignore the result & binding
    #   - `result` would be the returned value of the AST
    #   - `binding` would be the variables (none since everything is written to the process dictionary)
    {_result, _binding} = Code.eval_quoted(ast)

    # look at the next_transaction from the scope
    # return nil if it did not change
    case Map.get(Process.get(:scope), "next_transaction") do
      ^next_tx -> nil
      result_next_transaction -> result_next_transaction
    end
  end

  # ----------------------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  # ----------------------------------------------------------------------
  defp extract_trigger([{{:atom, "triggered_by"}, {{:atom, "transaction"}, _, nil}}]) do
    :transaction
  end

  defp extract_trigger([{{:atom, "triggered_by"}, {{:atom, "oracle"}, _, nil}}]) do
    :oracle
  end

  defp extract_trigger([
         {{:atom, "triggered_by"}, {{:atom, "interval"}, _, nil}},
         {{:atom, "at"}, cron_interval}
       ])
       when is_binary(cron_interval) do
    {:interval, cron_interval}
  end

  defp extract_trigger([
         {{:atom, "triggered_by"}, {{:atom, "datetime"}, _, nil}},
         {{:atom, "at"}, timestamp}
       ])
       when is_number(timestamp) do
    datetime = DateTime.from_unix!(timestamp)
    {:datetime, datetime}
  end

  defp parse_block(ast) do
    # here the accumulator is an list of parent scopes & current scope
    # where we can access variables from all of them
    # `acc = [ref1]` means read variable from scope.ref1 or scope
    # `acc = [ref1, ref2]` means read variable from scope.ref1.ref2 or scope.ref1 or scope
    acc = []

    {new_ast, _} =
      Macro.traverse(
        ast,
        acc,
        fn node, acc ->
          prewalk(node, acc)
        end,
        fn node, acc ->
          postwalk(node, acc)
        end
      )

    new_ast
  end

  # ----------------------------------------------------------------------
  #                                _ _
  #   _ __  _ __ _____      ____ _| | | __
  #  | '_ \| '__/ _ \ \ /\ / / _` | | |/ /
  #  | |_) | | |  __/\ V  V | (_| | |   <
  #  | .__/|_|  \___| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------
  # enter block == new scope
  defp prewalk(
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
        Process.put(
          :scope,
          put_in(Process.get(:scope), unquote(new_acc), %{})
        )
      end

    {
      {:__block__, meta, [create_scope_ast | expressions]},
      new_acc
    }
  end

  # whitelisted modules
  defp prewalk(
         node = {:__aliases__, _, [atom: module_name]},
         acc
       )
       when module_name in @modules_whitelisted do
    {node, acc}
  end

  # forbid "if" as an expression
  defp prewalk(
         node = {:=, _, [_, {:if, _, _}]},
         _acc
       ) do
    throw({:error, node, "Forbidden to use if as an expression."})
  end

  # forbid "for" as an expression
  defp prewalk(
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
  defp prewalk(
         _node = {:=, _, [{{:atom, var_name}, _, nil}, value]},
         acc
       ) do
    new_node =
      quote do
        Process.put(
          :scope,
          put_in(
            Process.get(:scope),
            Scope.where_to_assign_variable(Process.get(:scope), unquote(acc), unquote(var_name)) ++
              [unquote(var_name)],
            unquote(value)
          )
        )
      end

    {
      new_node,
      acc
    }
  end

  # Dot access non-nested (x.y)
  defp prewalk(_node = {{:., _, [{{:atom, map_name}, _, nil}, {:atom, key_name}]}, _, _}, acc) do
    new_node =
      quote do
        get_in(
          Process.get(:scope),
          Scope.where_to_assign_variable(Process.get(:scope), unquote(acc), unquote(map_name)) ++
            [unquote(map_name), unquote(key_name)]
        )
      end

    {new_node, acc}
  end

  # Dot access nested (x.y.z)
  defp prewalk({{:., _, [first_arg = {{:., _, _}, _, _}, {:atom, key_name}]}, _, []}, acc) do
    {nested, new_acc} = prewalk(first_arg, acc)

    new_node =
      quote do
        get_in(
          unquote(nested),
          [unquote(key_name)]
        )
      end

    {new_node, new_acc}
  end

  # for var: list
  defp prewalk(
         _node =
           {{:atom, "for"}, meta,
            [
              [{{:atom, var_name}, list}],
              [do: block]
            ]},
         acc
       ) do
    # wrap in a block to be able to pattern match it to create a scope
    ast =
      {{:atom, "for"}, meta,
       [
         [{{:atom, var_name}, list}],
         [do: AST.wrap_in_block(block)]
       ]}

    {ast, acc}
  end

  defp prewalk(
         node,
         acc
       ) do
    CommonInterpreter.prewalk(node, acc)
  end

  # ----------------------------------------------------------------------
  #                   _                 _ _
  #   _ __   ___  ___| |___      ____ _| | | __
  #  | '_ \ / _ \/ __| __\ \ /\ / / _` | | |/ /
  #  | |_) | (_) \__ | |_ \ V  V | (_| | |   <
  #  | .__/ \___/|___/\__| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------
  # exit block == set parent scope
  defp postwalk(
         node = {:__block__, _, _},
         acc
       ) do
    {node, List.delete_at(acc, -1)}
  end

  # Contract.get_calls() => Contract.get_calls(contract.address)
  defp postwalk(
         _node =
           {{:., _meta, [{:__aliases__, _, [atom: "Contract"]}, {:atom, "get_calls"}]}, _, []},
         acc
       ) do
    # contract is one of the "magic" variables that we expose to the user's code
    # it is bound in the root scope
    new_node =
      quote do
        Archethic.Contracts.Interpreter.Version1.Library.Contract.get_calls(
          get_in(
            Process.get(:scope),
            ["contract", "address"]
          )
        )
      end

    {new_node, acc}
  end

  # handle the Contract module
  # here we have 2 things to do:
  #   - feed the `next_transaction` as the 1st function parameter
  #   - update the `next_transaction` in scope
  defp postwalk(
         node =
           {{:., _meta, [{:__aliases__, _, [atom: "Contract"]}, {:atom, function_name}]}, _, args},
         acc
       ) do
    absolute_module_atom = Archethic.Contracts.Interpreter.Version1.Library.Contract

    # check function is available with given arity
    # (we add 1 to arity because we add the contract as 1st argument implicitely)
    unless Library.function_exists?(absolute_module_atom, function_name, length(args) + 1) do
      throw({:error, node, "invalid arity for function Contract.#{function_name}"})
    end

    function_atom = String.to_existing_atom(function_name)

    # check the type of the args
    unless absolute_module_atom.check_types(function_atom, args) do
      throw({:error, node, "invalid arguments for function Contract.#{function_name}"})
    end

    new_node =
      quote do
        Process.put(
          :scope,
          update_in(
            Process.get(:scope),
            ["next_transaction"],
            &apply(unquote(absolute_module_atom), unquote(function_atom), [&1 | unquote(args)])
          )
        )
      end

    {new_node, acc}
  end

  # variable are read from scope
  defp postwalk(
         _node = {{:atom, var_name}, _, nil},
         acc
       ) do
    new_node =
      quote do
        get_in(
          Process.get(:scope),
          Scope.where_to_assign_variable(Process.get(:scope), unquote(acc), unquote(var_name)) ++
            [unquote(var_name)]
        )
      end

    {new_node, acc}
  end

  # for var: list
  defp postwalk(
         _node =
           {{:atom, "for"}, _,
            [
              {:%{}, _, [{var_name, list}]},
              [do: block]
            ]},
         acc
       ) do
    # FIXME: here acc is already the parent acc, it is not the acc of the do block
    # FIXME: this means that our `var_name` will live in the parent scope
    # FIXME: it works (since we can read from parent) but it will override the parent binding if there's one

    # transform the for-loop into Enum.each
    # and create a variable in the scope
    new_node =
      quote do
        Enum.each(unquote(list), fn x ->
          Process.put(
            :scope,
            put_in(
              Process.get(:scope),
              unquote(acc) ++ [unquote(var_name)],
              x
            )
          )

          unquote(block)
        end)
      end

    {new_node, acc}
  end

  # --------------- catch all -------------------
  defp postwalk(node, acc) do
    CommonInterpreter.postwalk(node, acc)
  end
end
