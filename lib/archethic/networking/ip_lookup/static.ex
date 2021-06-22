defmodule ArchEthic.Networking.IPLookup.Static do
  @moduledoc """
  Module provides static IP address of the current node
  fetched from ENV variable or compile-time configuration.
  """

  alias ArchEthic.Networking.IPLookup.Impl

  @behaviour Impl

  @impl Impl
  @spec get_node_ip() :: {:ok, :inet.ip_address()} | {:error, :not_recognizable_ip}
  def get_node_ip do
    case Application.get_env(:archethic, __MODULE__) do
      nil ->
        {:ok, {127, 0, 0, 1}}

      conf ->
        hostname =
          conf
          |> Keyword.get(:hostname, "127.0.0.1")
          |> String.to_charlist()

        case :inet.parse_address(hostname) do
          {:ok, ip} ->
            {:ok, ip}

          _ ->
            {:error, :not_recognizable_ip}
        end
    end
  end
end
