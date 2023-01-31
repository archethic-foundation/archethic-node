defmodule Archethic.Contracts.Interpreter.ActionReduce do
  @moduledoc """
  AST manipulation related to the reduce/3
  """

  alias Archethic.Contracts.Interpreter.Utils
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  @reduce_item :sc_reduce_item
  @reduce_acc :sc_reduce_acc
  @reduce_scope :sc_reduce_scope

  @spec parse(any()) :: {:ok, Macro.t()} | {:error, term()}
  def parse(ast) do
    case Macro.traverse(
           ast,
           {:ok, %{scope: :root}},
           fn a, b ->
             # IO.inspect({a, b}, label: "prewalk")
             prewalk(a, b)
           end,
           fn a, b ->
             # IO.inspect({a, b}, label: "postwalk")
             postwalk(a, b)
           end
         ) do
      {node, {:ok, _}} ->
        {:ok, node}
    end
  catch
    {:error, reason, node} ->
      {:error, Utils.format_error_reason(node, reason)}

    {:error, node} ->
      {:error, Utils.format_error_reason(node, "unexpected term")}
  end

  @doc """
  Execute the code
  """
  @spec execute(Macro.t(), map()) :: Transaction.t()
  def execute(code, constants \\ %{}) do
    case Code.eval_quoted(code, scope: constants) do
      {acc, _ctx} ->
        # IO.inspect({acc, ctx}, label: "execute result")
        acc
    end
  end

  # ----------------------------------------------------------------------
  #
  #                      _ __  _ __ ___
  #                     | '_ \| '__/ _ \
  #                     | |_) | | |  __/
  #                     | .__/|_|  \___|
  #                     |_|
  #
  # ----------------------------------------------------------------------
  # ------- root ------------
  # enter in reduce_definition
  defp prewalk(
         node =
           {{:atom, "reduce"}, _,
            [
              firstArg,
              [
                {{:atom, "as"}, asVariable},
                {{:atom, "with"}, keywordList}
              ],
              [do: _]
            ]},
         {:ok, %{scope: :root}}
       ) do
    with true <-
           AST.is_variable?(firstArg) or
             AST.is_function_call?(firstArg) or
             AST.is_list?(firstArg),
         true <- AST.is_keyword_list?(keywordList),
         true <- AST.is_variable?(asVariable) do
      {node, {:ok, %{scope: :reduce_definition, parent_scope: :root}}}
    else
      false ->
        throw({:error, "invalid reduce syntax", node})
    end
  end

  # ------- reduce_definition ------------

  # ASK SAM TO PUT KEYWORD IN UTILS AND NOT IN ACTION
  # allow pairs
  defp prewalk(
         node = {{:atom, _}, _},
         acc = {:ok, %{scope: :reduce_definition}}
       ) do
    {node, acc}
  end

  defp prewalk(
         node = [do: _],
         _acc = {:ok, %{scope: :reduce_definition}}
       ) do
    {node, {:ok, %{scope: :reduce_block, parent_scope: :reduce_definition}}}
  end

  # pass through utils
  defp prewalk(
         node,
         acc = {:ok, %{scope: :reduce_definition}}
       ) do
    Utils.prewalk(node, acc)
  end

  # ------- reduce_block ------------
  # explicit forbid a reduce inside a reduce
  # this is already not allowed with scope, but this provide a helpful message to the user
  defp prewalk(
         node = {{:atom, "reduce"}, _, [_, _, _]},
         {:ok, %{scope: :reduce_block}}
       ) do
    throw({:error, "Nested reduce are forbidden", node})
  end

  # ASK SAM TO PUT ASSIGN IN UTILS AND NOT IN ACTION
  # allow pairs
  defp prewalk(
         node = {:=, _, _},
         acc = {:ok, %{scope: :reduce_block}}
       ) do
    {node, acc}
  end

  # pass through utils
  defp prewalk(
         node,
         acc = {:ok, %{scope: :reduce_block}}
       ) do
    Utils.prewalk(node, acc)
  end

  # ----------------------------------------------------------------------
  #                                      _
  #                      _ __   ___  ___| |_
  #                     | '_ \ / _ \/ __| __|
  #                     | |_) | (_) \__ | |_
  #                     | .__/ \___/|___/\__|
  #                     |_|
  #
  # ----------------------------------------------------------------------
  # Transform reduce into a list comprehension
  defp postwalk(
         _node =
           {{:atom, "reduce"}, _,
            [
              enumerable,
              [
                {{:atom, "as"}, {{:atom, itemName}, _, nil}},
                {{:atom, "with"}, withPropList}
              ],
              [do: block]
            ]},
         acc = {:ok, %{scope: :reduce_definition}}
       ) do
    # unwrap the {:atom, _} from the with proplist
    withPropList =
      withPropList
      |> Enum.map(fn {{:atom, atomName}, value} ->
        {atomName, value}
      end)

    # acc variables
    accVariables = withPropList |> Enum.map(&elem(&1, 0))

    # The block which is the content of the reduce is now going to be traversed
    # The prewalk is used to whitelist what is possible to do in a reduce
    # the postwalk is used to transform variable into the proper accessor
    {block, _} =
      Macro.traverse(
        block,
        :no_acc,
        fn
          # assignation
          node =
              {:=, meta,
               [
                 {{:atom, atomName}, _, nil},
                 content
               ]},
          acc0 ->
            cond do
              atomName == itemName ->
                throw({:error, ~s(Rebinding the "#{itemName}" variable is forbidden), node})

              atomName in accVariables ->
                # variable is in the "with"
                node =
                  {:=, meta,
                   [
                     {@reduce_acc, meta, nil},
                     {{:., meta, [{:__aliases__, meta, [:Map]}, :put]}, meta,
                      [{@reduce_acc, meta, nil}, atomName, content]}
                   ]}

                {node, acc0}

              true ->
                # variable is in the scope
                node =
                  {:=, meta,
                   [
                     {@reduce_scope, meta, nil},
                     {{:., meta, [{:__aliases__, meta, [:Map]}, :put]}, meta,
                      [{@reduce_scope, meta, nil}, atomName, content]}
                   ]}

                {node, acc0}
            end

          # pass through
          node, acc0 ->
            {node, acc0}
        end,
        fn
          # read variable
          {{:atom, atomName}, meta, nil}, acc0 ->
            node =
              cond do
                atomName == itemName ->
                  # variable is the "as"
                  {@reduce_item, meta, nil}

                atomName in accVariables ->
                  # variable is in the "with"
                  {{:., meta, [Access, :get]}, meta, [{@reduce_acc, meta, nil}, atomName]}

                true ->
                  # variable is in the scope
                  {{:., meta, [{:__aliases__, meta, [:Map]}, :get]}, meta,
                   [{@reduce_scope, meta, nil}, atomName]}
              end

            {node, acc0}

          # pass through
          node, acc0 ->
            {node, acc0}
        end
      )

    # Transform to an Enum.reduce
    node =
      {{:., [], [{:__aliases__, [alias: false], [:Enum]}, :reduce]}, [],
       [
         enumerable,
         {:%{}, [], withPropList},
         {:fn, [],
          [
            {:->, [],
             [
               [{@reduce_item, [], nil}, {@reduce_acc, [], nil}],
               {:__block__, [],
                [
                  # initiate a scope for the variables assigned within the reduce
                  {:=, [], [{@reduce_scope, [], nil}, {:%{}, [], []}]},

                  # user code
                  block,

                  # call the identity function on reduce_scope
                  # to avoid compilation warning if user do not use it
                  {{:., [], [{:__aliases__, [alias: false], [:Function]}, :identity]}, [],
                   [{@reduce_scope, [], nil}]},

                  # return the accumulator
                  {@reduce_acc, [], nil}
                ]}
             ]}
          ]}
       ]}

    {node, acc}
  end

  # exit the reduce scope
  defp postwalk(
         node = {{:atom, "reduce"}, _, [_, _, _]},
         {:ok, %{scope: :reduce_definition}}
       ) do
    {node, {:ok, %{scope: :root}}}
  end

  # exit the reduce block scope
  defp postwalk(
         node = [do: _],
         _acc = {:ok, %{scope: :reduce_block, parent_scope: parent_scope}}
       ) do
    {node, {:ok, %{scope: parent_scope}}}
  end

  # pass through
  defp postwalk(node, acc) do
    {node, acc}
  end
end
