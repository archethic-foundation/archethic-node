defmodule Archethic.Contracts.Interpreter.Version1.ActionInterpreter do
  @moduledoc false
  @modules_whitelisted ["Contract", "Transaction"]

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Contracts.Interpreter.Version1.CommonInterpreter
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  @doc """
  Parse the given node and return the trigger and the actions block.
  """
  @spec parse(Macro.t()) :: {:ok, atom(), Macro.t()} | {:error, Macro.t(), String.t()}
  def parse({{:atom, "actions"}, _, [keyword, [do: block]]}) do
    # We parse the outer block outside of the macro.traverse
    # so we can keep a clean acc that is used only for scoping variables.
    trigger_type = extract_trigger(keyword)
    actions_ast = parse_block(AST.wrap_in_block(block))
    {:ok, trigger_type, actions_ast}
  catch
    {:error, node} ->
      {:error, node, "unexpected term"}

    {:error, node, reason} ->
      {:error, node, reason}
  end

  @doc """
  Execute actions code and returns either the next transaction or nil
  """
  @spec execute(Macro.t(), map()) :: Transaction.t() | nil
  def execute(ast, constants \\ %{}) do
    :ok = Macro.validate(ast)

    IO.inspect(ast, label: "RESULTING AST")

    result =
      Code.eval_quoted(
        ast,
        [
          {
            {:scope, SmartContract},
            Map.put(constants, "next_transaction", %Transaction{
              data: %TransactionData{}
            })
          }
        ]
      )

    case result do
      {%{"next_transaction" => next_transaction}, _} ->
        next_transaction

      _ ->
        nil
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
    # here the accumulator is an list of reference
    # each reference is a scope
    # `acc = []` means read variable from scope
    # `acc = [ref1]` means read variable from scope.ref1 or scope
    # `acc = [ref1, ref2]` means read variable from scope.ref1.ref2 or scope.ref1 or scope
    acc = []

    {new_ast, _} =
      Macro.traverse(
        ast,
        acc,
        fn node, acc ->
          IO.inspect({node, acc}, label: "action prewalk")
          prewalk(node, acc)
        end,
        fn node, acc ->
          IO.inspect({node, acc}, label: "action postwalk")
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

  # --------------- block -------------------
  # whitelisted modules
  defp prewalk(
         node = {:__aliases__, _, [atom: moduleName]},
         acc
       )
       when moduleName in @modules_whitelisted do
    {node, acc}
  end

  # whitelist assignation & write them to scope
  # this is done in the prewalk because it must be done before the "variable are read from scope" step
  defp prewalk(
         _node = {:=, _, [{{:atom, varName}, _, nil}, value]},
         acc
       ) do
    new_node =
      quote context: SmartContract do
        scope = put_in(scope, [unquote(varName)], unquote(value))
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

  # --------------- block -------------------

  # handle the Contract module
  # here we have 2 things to do:
  #   - feed the `next_transaction` as the 1st function parameter
  #   - update the `next_transaction` in scope
  defp postwalk(
         _node =
           {{:., _meta, [{:__aliases__, _, [atom: "Contract"]}, {:atom, functionName}]}, _, args},
         acc
       ) do
    # ensure module is loaded (so the atoms corresponding to the functions exist)
    moduleAtom = Code.ensure_loaded!(Archethic.Contracts.Interpreter.Version1.Library.Contract)
    functionAtom = String.to_existing_atom(functionName)

    new_node =
      quote context: SmartContract do
        scope =
          update_in(
            scope,
            ["next_transaction"],
            &apply(unquote(moduleAtom), unquote(functionAtom), [&1 | unquote(args)])
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
      quote context: SmartContract do
        get_in(scope, [unquote(varName)])
      end

    {new_node, acc}
  end

  # --------------- catch all -------------------
  defp postwalk(node, acc) do
    CommonInterpreter.postwalk(node, acc)
  end
end
