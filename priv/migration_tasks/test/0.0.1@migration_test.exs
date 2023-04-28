defmodule Migration_0_0_1 do
  @moduledoc "DB.transaction_exists? used to catch it in MigrateTest mock"

  alias Archethic.DB

  def run() do
    DB.transaction_exists?("0.0.1", :storage)
  end
end
