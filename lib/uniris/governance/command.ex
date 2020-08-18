defmodule Uniris.Governance.Command do
  @moduledoc false

  @root_dir Application.get_env(:uniris, :src_dir)

  require Logger

  @doc """
  Execute a command on the system and return Stream
  """
  @spec execute(command :: binary, opts :: Keyword.t()) :: {:ok, binary()} | {:error, any()}
  def execute(command, opts \\ []) do
    log? = Keyword.get(opts, :log?, true)
    metadata = Keyword.get(opts, :metadata, [])
    env = Keyword.get(opts, :env, [])
    cd = Keyword.get(opts, :cd, @root_dir)

    if log? do
      Logger.info("Execute #{command} in #{cd}", metadata)
    end

    port =
      Port.open({:spawn, command}, [
        :stderr_to_stdout,
        :binary,
        :exit_status,
        cd: cd,
        env: env
      ])

    recv_loop(port, command, metadata, log?)
  end

  defp recv_loop(port, command, metadata, log?, acc \\ <<>>) do
    receive do
      {^port, {:data, data}} ->
        if log? do
          Logger.info(data, metadata)
        end

        recv_loop(port, command, metadata, log?, <<data::binary, acc::binary>>)

      {^port, {:exit_status, 0}} ->
        {:ok, String.split(acc, "\n", trim: true)}

      {^port, {:exit_status, status}} ->
        Logger.info("Error: #{status}")
        {:error, status}
    end
  end
end
