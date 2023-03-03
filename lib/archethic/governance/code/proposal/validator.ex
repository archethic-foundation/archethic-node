defmodule Archethic.Governance.Code.Proposal.Validator do
  @moduledoc """
  The Archethic Code Proposal Validator task is to validate Archethic Code Proposal.
  It is designed to run supervised by an os process with witch it communicates
  trough stdin/stdout.
  """
  require Logger

  alias Archethic.Utils.Regression

  @marker Application.compile_env(:archethic, :marker)

  def run(nodes, _) do
    start = System.monotonic_time(:second)

    with true <- Regression.nodes_up?(nodes),
         :ok <- Regression.run_benchmarks(nodes, phase: :before),
         :ok <- put_marker(nodes),
         _ <- Process.sleep(3 * 60 * 1000),
         :ok <- Regression.run_benchmarks(nodes, phase: :after),
         :ok <- Regression.run_playbooks(nodes),
         {:ok, _metrics} <-
           Regression.get_metrics("collector", 9090, 5 + System.monotonic_time(:second) - start) do
      :ok
    end
  end

  defp put_marker(args), do: IO.puts("#{@marker} | #{inspect(args)}")
end
