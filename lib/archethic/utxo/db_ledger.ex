defmodule Archethic.UTXO.DBLedger do
  @moduledoc false

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  use Knigge, otp_app: :archethic, default: __MODULE__.FileImpl

  @callback append(binary(), VersionedUnspentOutput.t()) :: :ok
  @callback append_list(binary(), list(VersionedUnspentOutput.t())) :: :ok
  @callback flush(binary(), list(VersionedUnspentOutput)) :: :ok
  @callback stream(binary()) :: list(VersionedUnspentOutput) | Enumerable.t()
  @callback list_genesis_addresses() :: list(binary())
end
