defmodule Archethic.Utils.DistinctEffectWorker do
  @moduledoc """
  The goal of this worker is to run an effect (a task that does not produce a result) at most once concurrently.
  """

  use GenServer
  @vsn Mix.Project.config()[:version]

  require Logger

  defstruct [
    :effect_fn,
    :next_fn,
    :task,
    inputs_processed: [],
    inputs_to_process: []
  ]

  # ------------------------------------------------------
  #               _
  #    __ _ _ __ (_)
  #   / _` | '_ \| |
  #  | (_| | |_) | |
  #   \__,_| .__/|_|
  #        |_|
  # ------------------------------------------------------
  @doc """
  Run the effect_fn at most once concurrently.
  """
  @spec run(term(), fun()) :: :ok
  def run(key, effect_fn) do
    run(
      key,
      effect_fn,
      &default_next_fn/2,
      [key]
    )
  end

  @doc """
  Run the effect_fn on given inputs at most once concurrently.
  Inputs are used to run multiple effects sequentially.
  The next_fn may be used to filter the inputs (e.g. remove dups)
  """
  @spec run(term(), fun(), fun(), list(term())) :: :ok
  def run(
        key,
        effect_fn,
        next_fn,
        inputs
      ) do
    # maybe start the worker
    case Registry.lookup(Archethic.Utils.DistinctEffectWorkerRegistry, key) do
      [] ->
        GenServer.start_link(
          __MODULE__,
          [effect_fn, next_fn],
          name: via_tuple(key)
        )

      _ ->
        :pass
    end

    # add the inputs
    GenServer.cast(via_tuple(key), {:add, inputs})
  end

  @doc """
  This function returns the inputs that have not been processed yet
  """
  def default_next_fn(inputs_to_process, inputs_processed) do
    Enum.filter(
      inputs_to_process,
      fn i ->
        i not in inputs_processed
      end
    )
  end

  # ------------------------------------------------------
  #            _ _ _                _
  #   ___ __ _| | | |__   __ _  ___| | _____
  #  / __/ _` | | | '_ \ / _` |/ __| |/ / __|
  # | (_| (_| | | | |_) | (_| | (__|   <\__ \
  #  \___\__,_|_|_|_.__/ \__,_|\___|_|\_|___/
  #
  # ------------------------------------------------------

  def init([effect_fn, next_fn]) do
    {:ok,
     %__MODULE__{
       effect_fn: effect_fn,
       next_fn: next_fn
     }}
  end

  # ------------------------------------------------------
  def handle_cast({:add, inputs}, state) do
    new_state = %__MODULE__{state | inputs_to_process: state.inputs_to_process ++ inputs}
    {:noreply, new_state, {:continue, :next}}
  end

  # ------------------------------------------------------
  def handle_info({_task_ref, _result}, state) do
    # we don't care about task result
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    new_state = %__MODULE__{state | task: nil}
    {:noreply, new_state, {:continue, :next}}
  end

  # ------------------------------------------------------
  def handle_continue(:next, state) do
    case state.next_fn.(state.inputs_to_process, state.inputs_processed) do
      [] ->
        {:stop, :normal, state}

      [input | rest] ->
        new_state = %__MODULE__{
          state
          | task:
              Task.async(fn ->
                state.effect_fn.(input)
              end),
            inputs_to_process: rest,
            inputs_processed: [input | state.inputs_processed]
        }

        {:noreply, new_state}
    end
  end

  # ------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  #
  # ------------------------------------------------------
  defp via_tuple(key) do
    {:via, Registry, {Archethic.Utils.DistinctEffectWorkerRegistry, key}}
  end
end
