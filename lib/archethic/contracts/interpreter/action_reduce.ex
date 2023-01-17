defmodule Archethic.Contracts.Interpreter.ActionReduce do
  @moduledoc """
  AST manipulation related to the reduce/3
  """

  @reduce_item_atom :ae_sc_reduce_item__
  @reduce_acc_atom :ae_sc_reduce_acc__

  # Whitelist the lambdas
  def prewalk(
        node = {:fn, _, [_]},
        acc
      ) do
    {node, acc}
  end

  # Whitelist the lambdas
  # Transforms the lambda args into hardcoded atoms in the entire context
  #
  # we do this because we don't want user to be able to create atoms (prevent atoms' table exhaustion)
  def prewalk(
        _node = {:->, meta, [args, body]},
        acc
      ) do
    # we know the lambda of a reduce has 2 arguments
    [
      {reduce_item_atom, reduce_item_meta, reduce_item_ctx},
      {reduce_acc_atom, reduce_acc_meta, reduce_acc_ctx}
    ] = args

    # replace them on the args node
    args_sanified = [
      {@reduce_item_atom, reduce_item_meta, reduce_item_ctx},
      {@reduce_acc_atom, reduce_acc_meta, reduce_acc_ctx}
    ]

    # replace them on the body node
    body_sanified =
      Macro.prewalk(body, fn
        body_node = {atom_name = {:atom, _}, meta, context} ->
          cond do
            atom_name == reduce_item_atom ->
              {@reduce_item_atom, meta, context}

            atom_name == reduce_acc_atom ->
              {@reduce_acc_atom, meta, context}

            true ->
              body_node
          end

        body_node ->
          body_node
      end)

    {{:->, meta, [args_sanified, body_sanified]}, acc}
  end

  # Whitelist the lambda 1st argument
  def prewalk(
        node = {@reduce_item_atom, _, _},
        acc
      ) do
    {node, acc}
  end

  # Whitelist the lambda 2nd argument
  def prewalk(
        node = {@reduce_acc_atom, _, _},
        acc
      ) do
    {node, acc}
  end

  # Whitelist every utils function inside the reducer
  def prewalk(node, acc) do
    Archethic.Contracts.Interpreter.Utils.prewalk(node, acc)
  end
end
