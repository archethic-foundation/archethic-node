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

  alias Archethic.Utils.JobCacheRegistry

  use GenServer
  @vsn 1

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
  @spec get!(GenServer.server(), Keyword.t()) :: any
  def get!(pid, opts \\ [])

  def get!(pid, opts) when is_pid(pid) do
    GenServer.call(pid, :get, Keyword.get(opts, :timeout, :infinity))
  end

  def get!(name, opts) when is_atom(name) do
    if Keyword.has_key?(opts, :function) do
      _ = start(Keyword.put(opts, :name, name))
    end

    GenServer.call(name, :get, Keyword.get(opts, :timeout, :infinity))
  end

  def get!(key, opts) do
    if Keyword.has_key?(opts, :function) do
      _ = start(Keyword.put(opts, :name, via_tuple(key)))
    end

    GenServer.call(via_tuple(key), :get, Keyword.get(opts, :timeout, :infinity))
  end

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
    * `:name` - if present, register the process with given name
    * `:name_key` - if present, register the process with given key to JobCacheRegistry

  ## Examples

      iex> #{__MODULE__}.start_link []
      ** (ArgumentError) expected :function in options

      iex> {:ok, pid} = #{__MODULE__}.start_link [function: fn -> :ok end, name: #{__MODULE__}]
      iex> #{__MODULE__}.get! pid
      :ok
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    name =
      case Keyword.get(opts, :name_key) do
        nil ->
          Keyword.get(opts, :name)

        key ->
          via_tuple(key)
      end

    Keyword.has_key?(opts, :function) || raise ArgumentError, "expected :function in options"
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec start(Keyword.t()) :: GenServer.on_start()
  def start(opts) do
    name =
      case Keyword.get(opts, :name_key) do
        nil ->
          Keyword.get(opts, :name)

        key ->
          via_tuple(key)
      end

    Keyword.has_key?(opts, :function) || raise ArgumentError, "expected :function in options"
    GenServer.start(__MODULE__, opts, name: name)
  end

  @spec stop(GenServer.server()) :: :ok
  def stop(pid) when is_pid(pid) do
    GenServer.stop(pid)
  catch
    :exit, _ -> :ok
  end

  def stop(name) when is_atom(name) do
    GenServer.stop(name)
  catch
    :exit, _ -> :ok
  end

  def stop(key) do
    GenServer.stop(via_tuple(key))
  catch
    :exit, _ -> :ok
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

  def handle_cast({:get_async, from}, state = %S{result: nil, task: nil, requests: requests}) do
    {:noreply, %S{state | task: Task.async(state.function), requests: [from | requests]}}
  end

  def handle_cast({:get_async, from}, state = %S{result: {:ok, res}, task: nil}) do
    GenServer.reply(from, res)
    {:noreply, state}
  end

  def handle_cast({:get_async, from}, state = %S{}) do
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

  defp via_tuple(key) do
    {:via, Registry, {JobCacheRegistry, key}}
  end
end
