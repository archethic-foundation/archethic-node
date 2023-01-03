defmodule ArchethicWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use ArchethicWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Phoenix.ConnTest

  alias ArchethicWeb.FaucetRateLimiter

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import ConnTest

      alias ArchethicWeb.ExplorerRouter.Helpers, as: Routes

      # The default endpoint for testing
      @endpoint ArchethicWeb.Endpoint
    end
  end

  setup _tags do
    # mark the node as bootstraped
    :persistent_term.put(:archethic_up, :up)

    start_supervised!(FaucetRateLimiter)
    {:ok, conn: ConnTest.build_conn()}
  end
end
