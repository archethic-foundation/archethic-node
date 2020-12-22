defmodule Uniris.Mining.MaliciousDetection do
  @moduledoc """
  Provide a process to detect the malicious nodes when the
  atomic commitment has not been reached.
  """

  alias Uniris.Mining.ValidationContext

  use Task

  @spec start_link(ValidationContext.t()) :: {:ok, pid()}
  def start_link(context = %ValidationContext{}) do
    Task.start_link(__MODULE__, :run, [context])
  end

  def run(_context = %ValidationContext{}) do
    # TODO: Implement the algorithm
  end
end
