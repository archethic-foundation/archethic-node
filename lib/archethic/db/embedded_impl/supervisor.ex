defmodule ArchEthic.DB.EmbeddedImpl.Supervisor do
  @moduledoc false

  use Supervisor

  alias ArchEthic.DB.EmbeddedImpl.Index
  alias ArchEthic.DB.EmbeddedImpl.Writer

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      Index,
      Writer
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
