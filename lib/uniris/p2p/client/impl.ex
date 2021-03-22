defmodule Uniris.P2P.ClientImpl do
  @moduledoc false

  alias Uniris.P2P.Client
  alias Uniris.P2P.Message
  alias Uniris.P2P.Node

  @callback send_message(Node.t(), Message.request(), timeout()) ::
              {:ok, Message.response()} | {:error, Client.error()}
end
