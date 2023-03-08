defmodule Archethic.Contracts.Interpreter.Version1.ActionInterpreter do
  @moduledoc false

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
    # constants should already contains the global variables:
    #   - "contract": current contract transaction
    #   - "transaction": the incoming transaction (when trigger=transaction)
    Scope.init(Map.put(constants, "next_transaction", next_tx))

    # we can ignore the result & binding
    #   - `result` would be the returned value of the AST
    #   - `binding` would be the variables (none since everything is written to the process dictionary)
    {_result, _binding} = Code.eval_quoted(ast)

    # look at the next_transaction from the scope
    # return nil if it did not change
    case Scope.read_global(["next_transaction"]) do
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
  # autorize the use of Contract module
  defp prewalk(
         node = {:__aliases__, _, [atom: "Contract"]},
         acc
       ) do
    {node, acc}
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
          Scope.read_global(["contract", "address"])
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

    # check function exists
    unless Library.function_exists?(absolute_module_atom, function_name) do
      throw({:error, node, "unknown function: Contract.#{function_name}"})
    end

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
        Scope.update_global(
          ["next_transaction"],
          &apply(unquote(absolute_module_atom), unquote(function_atom), [&1 | unquote(args)])
        )
      end

    {new_node, acc}
  end

  # --------------- catch all -------------------
  defp postwalk(node, acc) do
    CommonInterpreter.postwalk(node, acc)
  end
end
