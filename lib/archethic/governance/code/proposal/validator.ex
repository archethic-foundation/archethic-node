defmodule Archethic.Governance.Code.Proposal.Validator do
  @moduledoc """
  The Archethic Code Proposal Validator task is to validate Archethic Code Proposal.
  It is designed to run supervised by an os process with witch it communicates
  trough stdin/stdout.
  """
  require Logger

  alias Archethic.Utils.Regression

  @marker Application.compile_env(:archethic, :marker)

  def run(nodes, 1) do
    with true <- Regression.nodes_up?(nodes),
         :ok <- Regression.run_benchmarks(nodes, phase: :before) do
      put_marker(nodes)
    end
  end

  def run(nodes, 2) do
    start = System.monotonic_time(:second)

    with :ok <- Regression.run_benchmarks(nodes, phase: :after),
         :ok <- Regression.run_playbooks(nodes),
         {:ok, _metrics} <-
           Regression.get_metrics("collector", 9090, 5 + System.monotonic_time(:second) - start) do
      write_metrics(metrics)
    end
  end

  defp write_metrics(metrics),
    do: File.write!(Utils.mut_dir("metrics"), :erlang.term_to_iovec(metrics))

  defp put_marker(args), do: IO.puts("#{@marker} | #{inspect(args)}")
end
