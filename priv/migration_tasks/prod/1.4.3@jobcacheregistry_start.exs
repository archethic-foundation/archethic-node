defmodule Migration_1_4_3 do
  @moduledoc """
  Start the JobCacheRegistry which is a child of Application
  """

  def run() do
    {:ok, _} =
      Supervisor.start_child(
        Archethic.Supervisor,
        {Registry, keys: :unique, name: Archethic.Utils.JobCacheRegistry}
      )

    :ok
  end
end
