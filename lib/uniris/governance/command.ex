defmodule Uniris.Governance.Command do
  @moduledoc false

  @root_dir Application.get_env(:uniris, :src_dir)

  @doc """
  Execute a command on the system and return Stream
  """
  @spec execute(binary) :: Enumerable.t()
  def execute(command) do
    Stream.resource(
      fn ->
        Port.open({:spawn, command}, [:stderr_to_stdout, :line, :exit_status, cd: @root_dir])
      end,
      fn port ->
        receive do
          {^port, {:data, {:eol, data}}} ->
            {[data], port}

          {^port, {:exit_status, 0}} ->
            {:halt, port}

          {^port, {:exit_status, _status}} ->
            {:halt, port}
        end
      end,
      fn _port -> :ok end
    )
  end
end
