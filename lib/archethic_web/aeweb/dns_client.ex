defmodule ArchethicWeb.AEWeb.DNSClient do
  @moduledoc """
  Behavior for DNS lookup logic.
  """

  use Knigge, otp_app: :archethic, default: :inet_res

  @callback lookup(host :: binary(), class :: atom(), type :: atom(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}
end
