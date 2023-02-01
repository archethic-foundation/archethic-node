defmodule Archethic.Contracts.Interpreter.ActionReduce do
  @moduledoc """
  AST manipulation related to the reduce/3


  There are 3 scopes in here:

  - root
    we are not in the reduce yet (useful only to check the reduce syntax)

  - definition
    we are in the reduce statement

  - block
    we are in the do...end of the reduce
  """

  alias Archethic.Contracts.Interpreter.Utils
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  @reduce_item :sc_reduce_item
  @reduce_acc :sc_reduce_acc
  @reduce_scope :sc_reduce_scope
  @parent_scope :scope

  @doc """
  Return the initial accumulator, used by the parse functions
  """
  @spec initial_acc() :: :root
  def initial_acc() do
    :root
  end

  @spec add_scope_binding(Keyword.t()) :: Keyword.t()
  def add_scope_binding(keywords) do
    Keyword.put(keywords, @reduce_scope, %{})
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
  # ------- :root ------------
  # enter in reduce_definition
  def prewalk(
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
        :root
      ) do
    with true <-
           AST.is_variable?(firstArg) or
             AST.is_function_call?(firstArg) or
             is_list(firstArg),
         true <- AST.is_keyword_list?(keywordList),
         true <- AST.is_variable?(asVariable) do
      {node, :definition}
    else
      false ->
        throw({:error, "invalid reduce syntax", node})
    end
  end

  # ------- :definition ------------

  # ASK SAM TO PUT KEYWORD IN UTILS AND NOT IN ACTION
  # allow pairs
  def prewalk(
        node = {{:atom, _}, _},
        acc = :definition
      ) do
    {node, acc}
  end

  # enter the block scope
  def prewalk(
        node = [do: _],
        _acc = :definition
      ) do
    {node, :block}
  end

  # ------- :block ------------
  # explicit forbid a reduce inside a reduce
  # this is already not allowed with scope, but this provide a helpful message to the user
  def prewalk(
        node = {{:atom, "reduce"}, _, [_, _, _]},
        :block
      ) do
    throw({:error, "Nested reduce are forbidden", node})
  end

  # ASK SAM TO PUT ASSIGN IN UTILS AND NOT IN ACTION
  # allow pairs
  def prewalk(
        node = {:=, _, _},
        acc = :block
      ) do
    {node, acc}
  end

  # ASK SAM TO PUT KEYWORD IN UTILS AND NOT IN ACTION
  # allow pairs
  def prewalk(
        node = {{:atom, _}, _},
        acc = :block
      ) do
    {node, acc}
  end

  # pass through utils
  def prewalk(
        node,
        acc
      ) do
    # utils.prewalk require a weird acc
    {new_node, _} = Utils.prewalk(node, {:ok, %{scope: :reduce}})
    {new_node, acc}
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
  def postwalk(
        _node =
          {{:atom, "reduce"}, _,
           [
             list,
             [
               {{:atom, "as"}, {{:atom, itemName}, _, nil}},
               {{:atom, "with"}, withPropList}
             ],
             [do: block]
           ]},
        acc = :definition
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
          # DOT ACCESS
          {{:., meta,
            [
              {{:atom, mapName}, _, nil},
              {:atom, keyName}
            ]}, _, []},
          acc0 ->
            node =
              case mapName do
                "transaction" ->
                  # transaction.address =>
                  #
                  # Map.get(
                  #   Map.get(reduce_scope, "transaction", Map.get(scope, "transaction")),
                  #  "address"
                  # )
                  {{:., meta, [{:__aliases__, [alias: false], [:Map]}, :get]}, meta,
                   [
                     {{:., meta, [{:__aliases__, meta, [:Map]}, :get]}, meta,
                      [
                        {@reduce_scope, meta, nil},
                        mapName,
                        {{:., meta, [{:__aliases__, meta, [:Map]}, :get]}, meta,
                         [{@parent_scope, meta, nil}, mapName]}
                      ]},
                     keyName
                   ]}

                "contract" ->
                  # contract.address =>
                  #
                  # Map.get(
                  #   Map.get(reduce_scope, "contract", Map.get(scope, "contract")),
                  #  "address"
                  # )
                  {{:., meta, [{:__aliases__, [alias: false], [:Map]}, :get]}, meta,
                   [
                     {{:., meta, [{:__aliases__, meta, [:Map]}, :get]}, meta,
                      [
                        {@reduce_scope, meta, nil},
                        mapName,
                        {{:., meta, [{:__aliases__, meta, [:Map]}, :get]}, meta,
                         [{@parent_scope, meta, nil}, mapName]}
                      ]},
                     keyName
                   ]}

                _ ->
                  # Everything else is a proplist
                  #
                  # any.thing =>
                  #
                  # :proplists.get_value(
                  #   "thing",
                  #   Map.get(reduce_scope, "any", Map.get(scope, "any")),
                  #   :nil
                  # )
                  {{:., meta, [:proplists, :get_value]}, meta,
                   [
                     keyName,
                     {{:., meta, [{:__aliases__, [alias: false], [:Map]}, :get]}, meta,
                      [
                        {@reduce_scope, meta, nil},
                        mapName,
                        {{:., meta, [{:__aliases__, [alias: false], [:Map]}, :get]}, meta,
                         [{@parent_scope, meta, nil}, mapName]}
                      ]},
                     nil
                   ]}
              end

            {node, acc0}

          # ASSIGNATION
          node =
              {:=, meta,
               [
                 {{:atom, atomName}, _, nil},
                 content
               ]},
          acc0 ->
            cond do
              # left hand of = is the "as"
              atomName == itemName ->
                throw({:error, ~s(Rebinding the "#{itemName}" variable is forbidden), node})

              # left hand is a variable from the "with"
              atomName in accVariables ->
                # count = 0
                #
                # =>
                #
                # acc = Map.put(acc, "count", 0)
                node =
                  {:=, meta,
                   [
                     {@reduce_acc, meta, nil},
                     {{:., meta, [{:__aliases__, meta, [:Map]}, :put]}, meta,
                      [{@reduce_acc, meta, nil}, atomName, content]}
                   ]}

                {node, acc0}

              # left hand is an unknown variable
              true ->
                # other = 12
                #
                # =>
                #
                # reduce_scope = Map.put(reduce_scope, "other", 12)
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
          # ASK SAM TO PUT THIS IN UTILS
          # unwrap the {:atom, _} from keywords list
          node, acc0 when is_list(node) ->
            node =
              if AST.is_keyword_list?(node) do
                AST.keyword_to_proplist(node)
              else
                node
              end

            {node, acc0}

          # READ A VARIABLE
          {{:atom, atomName}, meta, nil}, acc0 ->
            node =
              cond do
                # variable is the "as"
                atomName == itemName ->
                  {@reduce_item, meta, nil}

                # variable is in the "with"
                atomName in accVariables ->
                  # count
                  #
                  # =>
                  #
                  # Access.get(acc, "count")
                  {{:., meta, [Access, :get]}, meta, [{@reduce_acc, meta, nil}, atomName]}

                # variable is an unknown variable (check :reduce_scope then @parent_scope)
                true ->
                  # other
                  #
                  # =>
                  #
                  # Map.get(reduce_scope, "other", Map.get(scope, "other"))
                  {{:., meta, [{:__aliases__, meta, [:Map]}, :get]}, meta,
                   [
                     {@reduce_scope, meta, nil},
                     atomName,
                     {{:., meta, [{:__aliases__, meta, [:Map]}, :get]}, meta,
                      [{@parent_scope, meta, nil}, atomName]}
                   ]}
              end

            {node, acc0}

          # pass through
          node, acc0 ->
            {node, acc0}
        end
      )

    # Transform to an Enum.reduce
    #
    # reduce list, as: item, with: [count: 0] do
    #   ...
    # end
    #
    # Enum.reduce(list, %{"count" => 0}, fn reduce_item, reduce_acc ->
    #   ...
    #   Function.identity(reduce_scope)
    #   reduce_acc
    # end)
    node =
      {{:., [], [{:__aliases__, [alias: false], [:Enum]}, :reduce]}, [],
       [
         list,
         {:%{}, [], withPropList},
         {:fn, [],
          [
            {:->, [],
             [
               [{@reduce_item, [], nil}, {@reduce_acc, [], nil}],
               {:__block__, [],
                [
                  # PROBABLY NOT NEEDED IF WE CREATE SCOPE IN THE EVAL_QUOTED
                  # # initiate a scope for the variables assigned within the reduce
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

  # exit the definition scope
  def postwalk(
        node = {{:atom, "reduce"}, _, [_, _, _]},
        :definition
      ) do
    {node, :root}
  end

  # exit the block scope
  def postwalk(
        node = [do: _],
        :block
      ) do
    {node, :definition}
  end

  # pass through
  def postwalk(node, acc) do
    {node, acc}
  end
end
