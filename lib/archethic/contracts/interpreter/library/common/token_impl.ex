defmodule Archethic.Contracts.Interpreter.Library.Common.TokenImpl do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library.Common.Token

  alias Archethic.Tag
  alias Archethic.Contracts.Interpreter.Legacy

  use Tag

  @tag [:io]
  @impl Archethic.Contracts.Interpreter.Library.Common.Token
  defdelegate fetch_id_from_address(address),
    to: Legacy.Library,
    as: :get_token_id
end
