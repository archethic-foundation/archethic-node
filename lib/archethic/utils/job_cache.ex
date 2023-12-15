defmodule Archethic.Utils.JobCache do
  @moduledoc """
  Provides cache for a heavy computation that should be performed sequentially.

  Simply using `Agent` to keep the result wouldn't work because heavy
  computation could be canceled on `#{__MODULE__}.clear`.

  ## Example

      iex> defmodule Heavy do
      iex>   def run do
      iex>     :persistent_term.put(:heavy, :called)
      iex>     :heavy
      iex>   end
      iex> end
      iex>
      iex> {:ok, cache} = #{__MODULE__}.start_link [function: &Heavy.run/0]
      iex>
      iex> #{__MODULE__}.get! cache
      :heavy
      iex> :persistent_term.get(:heavy)
      :called
      iex>
      iex> :persistent_term.erase(:heavy)
      iex> #{__MODULE__}.get! cache
      :heavy
      iex>
      iex> #{__MODULE__}.clear cache
      :ok
      iex> #{__MODULE__}.get! cache
      :heavy
      iex> :persistent_term.get(:heavy)
      :called
  """

  use GenServer
  @vsn Mix.Project.config()[:version]

  defmodule S do
    @moduledoc false
    defstruct([:task, :result, :function, requests: []])
  end

  @doc """
  Retrieves the result of the heavy computation from the cache or waits for it
  to finish. The computation is performed only once, even if it returns `nil`.

  ## Example

      iex> defmodule Nil do
      iex>   def run do
      iex>     :persistent_term.put(:nil, :called)
      iex>     nil
      iex>   end
      iex> end
      iex>
      iex> {:ok, cache} = #{__MODULE__}.start_link [function: &Nil.run/0]
      iex>
      iex> #{__MODULE__}.get! cache
      nil
      iex> :persistent_term.get(:nil)
      :called
      iex>
      iex> :persistent_term.erase(:nil)
      iex> #{__MODULE__}.get! cache
      nil
      iex>
      iex> #{__MODULE__}.clear cache
      :ok
      iex> #{__MODULE__}.get! cache
      nil
      iex> :persistent_term.get(:nil)
      :called
  """
  @spec get!(GenServer.server(), timeout) :: any
  def get!(pid \\ __MODULE__, timeout \\ :infinity), do: GenServer.call(pid, :get, timeout)

  @doc ~S"""
  Clears the result of a heavy computation, possibly by interrupting it if the
  computation is running
  """
  @spec clear(GenServer.server()) :: :ok
  def clear(pid \\ __MODULE__), do: GenServer.cast(pid, :clear)

  @doc """
  Starts `#{__MODULE__}`

  ## Options

    * `:function` - function
    * `:name` - if present, its value is passed to `GenServer.start_link/3`

  ## Examples

      iex> #{__MODULE__}.start_link []
      ** (ArgumentError) expected :function in options

      iex> {:ok, _} = #{__MODULE__}.start_link [function: fn -> :ok end, name: #{__MODULE__}]
      iex> #{__MODULE__}.get!
      :ok
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    Keyword.has_key?(opts, :function) || raise ArgumentError, "expected :function in options"
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @spec start(Keyword.t()) :: GenServer.on_start()
  def start(opts) do
    Keyword.has_key?(opts, :function) || raise ArgumentError, "expected :function in options"
    GenServer.start(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @impl GenServer
  def init(opts) do
    function = Keyword.fetch!(opts, :function)
    immediate = Keyword.get(opts, :immediate, false)

    if immediate do
      {:ok, %S{function: function, task: Task.async(function)}}
    else
      {:ok, %S{function: function}}
    end
  end

  @impl GenServer
  def handle_call(:get, from, state = %S{result: nil, task: nil, requests: requests}) do
    {:noreply, %S{state | task: Task.async(state.function), requests: [from | requests]}}
  end

  def handle_call(:get, _from, state = %S{result: {:ok, res}, task: nil}) do
    {:reply, res, state}
  end

  def handle_call(:get, from, state = %S{}) do
    {:noreply, %S{state | requests: [from | state.requests]}}
  end

  @impl GenServer
  def handle_cast(:clear, state = %S{task: nil}) do
    {:noreply, %S{state | result: nil}}
  end

  def handle_cast(:clear, state = %S{task: task}) do
    Task.shutdown(task)
    {:noreply, %S{state | result: nil, task: Task.async(state.function)}}
  end

  @impl GenServer
  def handle_info({ref, result}, state = %S{task: %Task{ref: ref}}) do
    state.requests |> Enum.each(&GenServer.reply(&1, result))
    {:noreply, %S{state | task: nil, result: {:ok, result}, requests: []}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end
end
