defmodule Archethic.Utils.JobConductor do
  @moduledoc ~S"""
  Conducts heavy computations in a restrictive way by limiting the number of
  concurrently running computations, by default to 1.

  ## Example

      iex> f = fn x ->
      iex>   :persistent_term.put("s_#{x}", System.system_time)
      iex>   Process.sleep(50)
      iex>   :persistent_term.put("e_#{x}", System.system_time)
      iex>   :done
      iex> end
      iex>
      iex> {:ok, _} = JobConductor.start_link [name: JobConductor]
      iex>
      iex> spawn(fn -> JobConductor.conduct f, [1] end)
      iex> spawn(fn -> JobConductor.conduct f, [2] end)
      iex> Process.sleep(5) # let spawned calls some time to spawn
      iex>
      iex> JobConductor.conduct f, [3]
      {:ok, :done}
      iex>
      iex> e1 = :persistent_term.get("e_1")
      iex> s2 = :persistent_term.get("s_2")
      iex> e2 = :persistent_term.get("e_2")
      iex> s3 = :persistent_term.get("s_3")
      iex> e1 < s2 and e2 < s3
      true
  """
  @typedoc "Return value of `conduct` function"
  @type conduct :: {:ok, any} | {:caught, any} | {:rescued, any}

  use GenServer
  @vsn 1

  defmodule S do
    @moduledoc false
    defstruct(running: 0, limit: 1, q: :queue.new())
  end

  @doc ~S"""
  Calls `Kernel.apply/2` with the given `function` and `args` when it has an
  opportunity and returns {:ok, result} or {:caught, what}, or {:rescued, what}

  ## Example

      iex> {:ok, c} = JobConductor.start_link []
      iex>
      iex> JobConductor.conduct(fn -> :done end, [], c)
      {:ok, :done}
      iex>
      iex> JobConductor.conduct(fn -> raise "exception" end, [], c)
      {:rescued, %RuntimeError{message: "exception"}}
      iex>
      iex> JobConductor.conduct(fn -> throw :garbage end, [], c)
      {:caught, :garbage}
  """
  @spec conduct(function, [any], GenServer.server(), timeout) :: conduct
  def conduct(fun, args \\ [], pid \\ __MODULE__, timeout \\ :infinity) do
    GenServer.call(pid, {:conduct, fun, args}, timeout)
  end

  @doc ~S"""
  Starts a `Archethic.JobConductor` process linked to the current process.

  ## Options

    * `:name` - if present, its value is passed to `GenServer.start_link/3`
    * `:limit` - if present, sets the limit of concurrency, the default is 1
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

  @impl GenServer
  def init(opts) do
    {:ok, %S{limit: Keyword.get(opts, :limit, 1)}}
  end

  @impl GenServer
  def handle_call({:conduct, fun, args}, from, %S{running: r, limit: l, q: q} = state)
      when r < l do
    case :queue.out(q) do
      {:empty, _} ->
        Task.async(fn -> do_conduct(fun, args, from) end)
        {:noreply, %S{state | running: r + 1}}

      {{:value, {fun0, args0, from0}}, q1} ->
        Task.async(fn -> do_conduct(fun0, args0, from0) end)
        {:noreply, %S{state | running: r + 1, q: :queue.in({fun, args, from}, q1)}}
    end
  end

  def handle_call({:conduct, fun, args}, from, state = %S{q: q}) do
    {:noreply, %S{state | q: :queue.in({fun, args, from}, q)}}
  end

  @impl GenServer
  def handle_info({_ref, _result}, state), do: {:noreply, state}

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state = %S{running: r, q: q}) do
    case :queue.out(q) do
      {:empty, _} ->
        {:noreply, %S{state | running: r - 1}}

      {{:value, {fun0, args0, from0}}, q1} ->
        Task.async(fn -> do_conduct(fun0, args0, from0) end)
        {:noreply, %S{state | q: q1}}
    end
  end

  defp do_conduct(fun, args, from) do
    apply(fun, args)
  rescue
    value ->
      GenServer.reply(from, {:rescued, value})
  catch
    value ->
      GenServer.reply(from, {:caught, value})
  else
    value ->
      GenServer.reply(from, {:ok, value})
  end
end
