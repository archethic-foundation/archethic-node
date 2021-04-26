defmodule Uniris.P2P.Client do
  @moduledoc false

  alias Uniris.Crypto

  alias Uniris.P2P.Client.DefaultImpl
  alias Uniris.P2P.Message
  alias Uniris.P2P.Node
  alias Uniris.P2P.Transport

  @doc """
  Create a new node client connection for a remote node
  """
  @spec new_connection(
          :inet.ip_address(),
          port :: :inet.port_number(),
          Transport.supported(),
          Crypto.key()
        ) :: {:ok, pid()}
  def new_connection(ip, port, transport, first_public_key) do
    impl().new_connection(ip, port, transport, first_public_key)
  end

  @doc """
  Send a message to a remote node
  """
  @spec send_message(Node.t(), Message.request()) ::
          {:ok, Message.response()} | {:error, :network_issue}
  def send_message(node = %Node{}, msg) do
    impl().send_message(node, msg)
  end

  defp impl do
    :uniris
    |> Application.get_env(__MODULE__, impl: DefaultImpl)
    |> Keyword.fetch!(:impl)
  end
end
