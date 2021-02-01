defmodule Uniris.Governance.Code.CICD do
  @moduledoc false

  alias Uniris.Governance.Code.Proposal

  @doc """
  Start CICD
  """
  @callback start_link(Keyword.t()) :: GenServer.on_start()

  @doc """
  Execute the continuous integration of the code proposal
  """
  @callback run_ci!(Proposal.t()) :: :ok

  @doc """
  Return CI log from the proposal address
  """
  @callback get_log(binary()) :: {:ok, binary()} | {:error, term}

  @doc """
  ??? TODO
  """
  @callback run_testnet!(Proposal.t(), Keyword.t()) :: :ok

  @doc """
  ??? TODO
  """
  @callback clean(address :: binary()) :: :ok
end
