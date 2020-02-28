defmodule UnirisP2P do
  @moduledoc """
  Interface for P2P node communication responsible to spawn process for each P2P client and communicate with

  Curent implementation using :gen_tcp to keep long living connection and monitor any flews
  """

  @behaviour UnirisNetwork.P2P.ClientImpl

  @doc """
  Spawn a monitored connection to remote node

  Using an active P2P client such as GenServer, it receives messages
  from the remote node (ie. data response, connection closed, miscellanous errors) and notify the parent (the one which spawn the process) about all these messages
  """
  @impl true
  @spec start_link(
          ip_address :: :inet.ip_address(),
          port :: :inet.port_number(),
          node_public_key :: UnirisCrypto.key(),
          from :: pid()
        ) :: {:ok, pid()}
  def start_link(ip, port, public_key, from) do
    client_impl().start_link(ip, port, public_key, from)
  end

  @doc """
  Send asynchronously a message to a remote node by encoding the message and decoding the response and notify it to the process owner
  """
  @impl true
  @spec send_message(UnirisCrypto.key(), term()) :: :ok
  def send_message(public_key, message) do
    client_impl().send_message(public_key, message)
  end

  defp client_impl() do
    Application.get_env(:uniris_p2p, :client, __MODULE__.TCPClient)
  end
end
