defmodule Archethic.Contracts.Interpreter.Library.Common.ChainImpl do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library.Common.Chain

  alias Archethic.Contracts.Interpreter.Legacy

  @impl Archethic.Contracts.Interpreter.Library.Common.Chain
  defdelegate get_genesis_address(address),
    to: Legacy.Library,
    as: :get_genesis_address

  @impl Archethic.Contracts.Interpreter.Library.Common.Chain
  defdelegate get_first_transaction_address(address),
    to: Legacy.Library,
    as: :get_first_transaction_address

  @impl Archethic.Contracts.Interpreter.Library.Common.Chain
  defdelegate get_genesis_public_key(public_key),
    to: Legacy.Library,
    as: :get_genesis_public_key
end
