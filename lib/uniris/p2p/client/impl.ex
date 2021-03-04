defmodule Uniris.P2P.ClientImpl do
  @moduledoc false

  alias Uniris.P2P.Client
  alias Uniris.P2P.Message
  alias Uniris.P2P.Node

  @callback send_message(Node.t(), Message.t()) ::
              {:ok, Message.t()} | {:error, Client.error()}
end
