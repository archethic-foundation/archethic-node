defmodule Uniris.P2P.TransportImpl do
  @moduledoc false

  alias Uniris.P2P.Message

  @callback listen(:inet.port_number()) ::
              {:ok, :inet.socket()} | {:error, reason :: :system_limit | :inet.posix()}
  @callback accept(:inet.socket()) :: :ok
  @callback send_message(:inet.ip_address(), :inet.port_number(), Message.t()) ::
              {:ok, Message.t()} | {:error, reason :: :timeout | :inet.posix()}
end
