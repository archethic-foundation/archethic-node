defmodule UnirisNetwork.ChainLoader do
  @moduledoc false

  use Task

  def start_link(_) do
    Task.start_link(__MODULE__, :run, [])
  end

  def run() do
    Task.start(fn -> load_shared_secrets() end)
    Task.start(fn -> load_nodes() end)
  end

  defp load_shared_secrets() do
    # TODO: retrieve last shared secret transaction chain
    # TODO: fill ETS table with

  end

  defp load_nodes() do
    # TODO: retrieve node transaction chains
    # TODO: fill ETS tables with
    # TODO: set up NodeView FSM for each node to keep their P2P view
  end
end
