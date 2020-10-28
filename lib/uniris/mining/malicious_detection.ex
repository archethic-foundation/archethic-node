defmodule Uniris.Mining.MaliciousDetection do
  @moduledoc """
  Provide a process to detect the malicious nodes when the
  atomic commitment has not been reached.
  """

  use Task

  def start_link(args) do
    Task.start_link(__MODULE__, :run, args)
  end

  def run(_) do
    # TODO: Implement the algorithm
  end
end
