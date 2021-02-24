defmodule Uniris.P2P.TransportImpl do
  @moduledoc false

  @callback listen(:inet.port_number(), options :: list()) ::
              {:ok, :inet.socket()} | {:error, reason :: :system_limit | :inet.posix()}

  @callback send_message(socket :: :inet.socket(), message :: binary()) ::
              :ok | {:error, :closed | :inet.posix()}

  @callback connect(
              ip :: :inet.ip_address(),
              port :: :inet.port_number(),
              options :: list(),
              timeout :: non_neg_integer()
            ) :: {:ok, :inet.socket()} | {:error, :timeout | :inet.posix()}

  @callback read_from_socket(
              :inet.socket(),
              (binary() -> :ok),
              size_to_read :: non_neg_integer(),
              timeout :: non_neg_integer()
            ) :: :ok | {:error, :closed | :timeout | :inet.posix()}
end
