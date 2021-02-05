defmodule Uniris.P2P.Client do
  @moduledoc false

  alias Uniris.P2P.Client.TransportImpl
  alias Uniris.P2P.Message
  alias Uniris.P2P.Node

  require Logger

  @doc """
  Send a message to a remote node
  """
  @spec send_message(Node.t(), Message.t()) :: Message.t()
  def send_message(node = %Node{}, msg) do
    impl().send_message(node, msg)
  rescue
    e ->
      Logger.error(e)
  end

  defp impl do
    :uniris
    |> Application.get_env(__MODULE__, impl: TransportImpl)
    |> Keyword.fetch!(:impl)
  end
end
