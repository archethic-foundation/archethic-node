defmodule Archethic.Contracts.Interpreter.Logs do
  @moduledoc """
  Helper module to help with logs I/O
  """

  @type t() :: list(log())
  @type log() :: {DateTime.t(), term()}
  @process_key :playground_logs

  @spec append(term()) :: :ok
  def append(term) do
    Process.put(@process_key, [
      {DateTime.utc_now(), term} | Process.get(@process_key, [])
    ])

    :ok
  end

  @spec reset() :: :ok
  def reset() do
    Process.put(@process_key, [])
    :ok
  end

  @spec all() :: t()
  def all() do
    Process.get(@process_key, [])
    |> Enum.reverse()
  end
end
