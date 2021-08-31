defmodule ArchEthic.Governance.Code.Proposal.Validator do
  @moduledoc """
  The ArchEthic Code Proposal Validator task is to validate ArchEthic Code Proposal.
  It is designed to run supervised by an os process with witch it communicates
  trough stdin/stdout.
  """
  require Logger

  alias ArchEthic.Utils
  alias ArchEthic.Utils.Regression

  @marker Application.compile_env(:archethic, :marker)

  def run(nodes) do
    start = System.monotonic_time(:second)

    with true <- Regression.nodes_up?(nodes),
         :ok <- Regression.run_benchmarks(nodes, phase: :before),
         :ok <- await_upgrade(nodes),
         :ok <- Regression.run_benchmarks(nodes, phase: :after),
         :ok <- Regression.run_playbooks(nodes),
         {:ok, metrics} <-
           Regression.get_metrics("collector", 9090, 5 + System.monotonic_time(:second) - start) do
      File.write!(Utils.mut_dir("metrics"), :erlang.term_to_iovec(metrics))
    end
  end

  defp await_upgrade(args) do
    IO.puts("#{@marker} | #{inspect(args)}")
    Port.open({:fd, 0, 1}, [:out, {:line, 256}]) |> Port.command("")
    IO.gets("Continue? ") |> IO.puts()
  end
end
