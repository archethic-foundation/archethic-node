defmodule Uniris.Mining.MaliciousDetection do
  @moduledoc """
  Provide a process to detect the malicious nodes when the
  atomic commitment has not been reached.

  # TODO: Implement the algorithm
  """
  use Task

  alias Uniris.Transaction

  def start_link(opts) do
    tx = Keyword.get(opts, :transaction)
    Task.start_link(__MODULE__, :run, [tx])
  end

  def run(_tx = %Transaction{}) do
  end
end
