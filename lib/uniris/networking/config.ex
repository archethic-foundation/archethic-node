defmodule Uniris.Networking.Config do
  @moduledoc """
  Module provides configuration assets for Networking module.
  """

  # Public

  @spec get_p2p_port() :: {:ok, pos_integer} | {:error, :invalid_port} | {:error, any()}
  def get_p2p_port do
    with config when not is_nil(config) <- Application.get_env(:uniris, Uniris.Networking),
    {:ok, port} when is_integer(port) <- Keyword.fetch(config, :port) do
      {:ok, port}
    else
      nil -> {:error, :invalid_port}
      :error -> {:error, :invalid_port} 
      {:ok, _not_integer} -> {:error, :invalid_port} 
    end
  end
end