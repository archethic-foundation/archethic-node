defmodule Uniris.Governance.CommandLogger.FileImpl do
  @moduledoc false

  @behaviour Uniris.Governance.CommandLogger.Impl

  @spec write(binary, Keyword.t()) :: :ok
  @impl true
  def write(_data, []), do: :ok

  def write(data, address: address)
      when is_binary(data) and is_binary(address) do
    file = Application.app_dir(:uniris, "priv/proposal/#{Base.encode16(address)}")
    File.write("#{data}\n", file, [:append])
  end
end
