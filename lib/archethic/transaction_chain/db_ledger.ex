defmodule Archethic.TransactionChain.DBLedger do
  @moduledoc """
  Manage DB for transaction's chain
  """

  alias Archethic.TransactionChain.VersionedTransactionInput

  use Knigge, otp_app: :archethic, default: __MODULE__.FileImpl

  @callback write_inputs(binary(), list(VersionedTransactionInput.t())) :: :ok
  @callback stream_inputs(binary()) :: Enumerable.t() | list(VersionedTransactionInput.t())
end
