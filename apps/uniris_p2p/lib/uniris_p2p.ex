defmodule UnirisP2P do
  @moduledoc """
  Interface for P2P node communication responsible to spawn process for each P2P client
  """

  alias __MODULE__.Client

  @doc """
  Establishes a connection to remote node
  """
  @spec connect(:inet.ip_address(), :inet.port_number(), binary()) :: :ok
  def connect(ip, port, public_key) do
    Client.connect(ip, port, public_key, self())
  end

  @doc """
  Send asynchronously a message to a remote node
  """
  @spec send(binary(), term()) :: :ok
  def send(public_key, message) do
    Client.send_message(public_key, message)
  end

  defp impl() do
    Application.get_env(:uniris_p2p, :client, __MODULE__.TCPClient)
  end
end
