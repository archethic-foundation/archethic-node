defmodule Archethic.Account.GenesisSupervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Account.GenesisLoader
  alias Archethic.Account.GenesisLoaderSupervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Archethic.AccountGenesisSupervisor)
  end

  def init(_) do
    GenesisLoader.setup_folders!()

    children = [
      {PartitionSupervisor,
       child_spec: GenesisLoader, name: GenesisLoaderSupervisor, partitions: 20}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
