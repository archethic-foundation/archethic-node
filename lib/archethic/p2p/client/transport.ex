defmodule Archethic.P2P.Client.Transport do
  @moduledoc false

  @callback handle_connect(:inet.ip_address(), :inet.port_number()) :: {:ok, :inet.socket()}
  @callback handle_message(tuple()) :: {:ok, binary()} | {:error, :closed} | {:error, any()}
  @callback handle_send(:inet.socket(), binary()) :: :ok
  @callback handle_close(:inet.socket()) :: :ok
end
