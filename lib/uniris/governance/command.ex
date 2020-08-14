defmodule Uniris.Governance.Command do
  @moduledoc false

  alias Uniris.Governance.CommandLogger

  @root_dir Application.get_env(:uniris, :src_dir)

  @doc """
  Execute a command on the system and return Stream
  """
  @spec execute(binary, Keyword.t()) :: Enumerable.t()
  def execute(command, metadata \\ []) do
    CommandLogger.write("Executing command: #{command}", metadata)

    Stream.resource(
      fn ->
        Port.open({:spawn, command}, [
          :stderr_to_stdout,
          :line,
          :binary,
          :exit_status,
          cd: @root_dir
        ])
      end,
      fn port ->
        receive do
          {^port, {:data, {:eol, data}}} ->
            {[to_string(data)], port}

          {^port, {:exit_status, 0}} ->
            {:halt, port}

          {^port, {:exit_status, _status}} ->
            {:halt, port}
        end
      end,
      fn _port -> :ok end
    )
    |> Stream.each(&CommandLogger.write(&1, metadata))
  end
end
