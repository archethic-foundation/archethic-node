defmodule UnirisCore.Mining.MaliciousDetection do
  use Task

  alias UnirisCore.Transaction

  def start_link(opts) do
    tx = Keyword.get(opts, :transaction)
    Task.start_link(__MODULE__, :run, [tx])
  end

  def run(_tx = %Transaction{}) do
  end
end
