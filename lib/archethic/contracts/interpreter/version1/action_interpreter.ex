defmodule Archethic.Contracts.Interpreter.Version1.ActionInterpreter do
  @moduledoc false
  @modules_whitelisted ["Contract", "Transaction"]

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Version1.CommonInterpreter
  alias Archethic.Contracts.Interpreter.Version1.Library
  alias Archethic.Contracts.Interpreter.Version1.Scope

  @doc """
  Parse the given node and return the trigger and the actions block.
  """
  @spec parse(Macro.t()) :: {:ok, atom(), Macro.t()} | {:error, Macro.t(), String.t()}
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
  @spec execute(Macro.t(), map()) :: Transaction.t() | nil
  def execute(ast, constants \\ %{}) do
    :ok = Macro.validate(ast)

    # we use the process dictionary to store our scope
    # because it is mutable.
    Process.put(
      :scope,
      Map.put(constants, "next_transaction", %Transaction{
        data: %TransactionData{}
      })
    )

    # we can ignore the result & binding
    #   - `result` would be the returned value of the AST
    #   - `binding` would be the variables (none since everything is written to the process dictionary)
    {_result, _binding} = Code.eval_quoted(ast)

    # look at the next_transaction from the scope
    Map.get(Process.get(:scope), "next_transaction")
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
         {{:atom, "at"}, cronInterval}
       ])
       when is_binary(cronInterval) do
    {:interval, cronInterval}
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
    # references are not AST valid, so we convert them to charlist
    ref = :erlang.ref_to_list(make_ref())
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
         node = {:__aliases__, _, [atom: moduleName]},
         acc
       )
       when moduleName in @modules_whitelisted do
    {node, acc}
  end

  # forbid "if" as an expression
  defp prewalk(
         node = {:=, _, [_, {:if, _, _}]},
         _acc
       ) do
    throw({:error, node, "Forbidden to use if as an expression."})
  end

  # whitelist assignation & write them to scope
  # this is done in the prewalk because it must be done before the "variable are read from scope" step
  defp prewalk(
         _node = {:=, _, [{{:atom, varName}, _, nil}, value]},
         acc
       ) do
    new_node =
      quote do
        Process.put(
          :scope,
          put_in(
            Process.get(:scope),
            Scope.where_to_assign_variable(Process.get(:scope), unquote(acc), unquote(varName)) ++
              [unquote(varName)],
            unquote(value)
          )
        )
      end

    {
      new_node,
      acc
    }
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

  # handle the Contract module
  # here we have 2 things to do:
  #   - feed the `next_transaction` as the 1st function parameter
  #   - update the `next_transaction` in scope
  defp postwalk(
         node =
           {{:., _meta, [{:__aliases__, _, [atom: "Contract"]}, {:atom, functionName}]}, _, args},
         acc
       ) do
    absoluteModuleAtom = Archethic.Contracts.Interpreter.Version1.Library.Contract

    # check function is available with given arity
    # (we add 1 to arity because we add the contract as 1st argument implicitely)
    unless Library.function_exists?(absoluteModuleAtom, functionName, length(args) + 1) do
      throw({:error, node, "invalid arity for function Contract.#{functionName}"})
    end

    functionAtom = String.to_existing_atom(functionName)

    # check the type of the args
    unless absoluteModuleAtom.check_types(functionAtom, args) do
      throw({:error, node, "invalid arguments for function Contract.#{functionName}"})
    end

    new_node =
      quote do
        Process.put(
          :scope,
          update_in(
            Process.get(:scope),
            ["next_transaction"],
            &apply(unquote(absoluteModuleAtom), unquote(functionAtom), [&1 | unquote(args)])
          )
        )
      end

    {new_node, acc}
  end

  # modify the alias of whitelisted modules
  defp postwalk(
         _node =
           {{:., meta, [{:__aliases__, _, [atom: moduleName]}, {:atom, functionName}]}, _, args},
         acc
       )
       when moduleName in @modules_whitelisted do
    moduleAtom = String.to_existing_atom(moduleName)
    functionAtom = String.to_existing_atom(functionName)

    aliasAtom =
      String.to_existing_atom(
        "Elixir.Archethic.Contracts.Interpreter.Version1.Library.#{moduleName}"
      )

    meta_with_alias = Keyword.put(meta, :alias, aliasAtom)

    new_node =
      {{:., meta, [{:__aliases__, meta_with_alias, [moduleAtom]}, functionAtom]}, meta, args}

    {new_node, acc}
  end

  # variable are read from scope
  defp postwalk(
         _node = {{:atom, varName}, _, nil},
         acc
       ) do
    new_node =
      quote do
        # FIXME Map.fetch!
        get_in(
          Process.get(:scope),
          Scope.where_to_assign_variable(Process.get(:scope), unquote(acc), unquote(varName)) ++
            [unquote(varName)]
        )
      end

    {new_node, acc}
  end

  # --------------- catch all -------------------
  defp postwalk(node, acc) do
    CommonInterpreter.postwalk(node, acc)
  end
end
