defmodule Uniris.Governance.Code.CICD do
  @moduledoc ~S"""
  Provides CICD pipeline for `Uniris.Governance.Code.Proposal`

  The evolution of uniris-node could be represented using following stages:

    * Init - when source code is copiled into uniris-node (not covered here)
    * CI - uniris-node is verifying a proposal and generating a release upgrade
    * CD - uniris-node is forking a testnet to verify release upgrade

  In each stage a transition from a source to a result could happen

      | Stage | Source           | Transition   | Result         |
      |-------+------------------+--------------+----------------|
      | Init  | Code             | compile      | Release        |
      | CI    | Code, Proposal   | run CI tests | CiLog, Upgrade |
      | CD    | Release, Upgrade | run testnet  | TnLog, Release |

  where
    * Code - a source code of uniris-node
    * Propsal - a code proposal transaction
    * Release - a release of uniris-node
    * Upgrade - an upgrade to a release of uniris-node
    * CiLog - unit tests and type checker logs
    * TnLog - logs retrieved from running testnet fork

  ## CI
  Given a `Code.Proposal` the `CICD.run_ci!/1` creates a log of application of
  the `Proposal` to the `Code` and a release upgrade which is a delta between
  previous release and new release.

  ## CD
  TODO describe what happens with release upgrade
  """

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
