defmodule Uniris.Governance.Code.CICD do
  @moduledoc ~S"""
  Provides CICD pipeline for `Uniris.Governance.Code.Proposal`

  The evolution of uniris-node could be represented using following stages:

    * Init - when source code is compiled into uniris-node (not covered here)
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
  Given a `Code.Proposal` the `CICD.run_ci!/1` should generate: a log of
  application of the `Proposal` to the `Code`, a release upgrade which is a
  delta between previous release and new release, and a new version of
  `uniris-proposal-validator` escript.

  ## CD
  Given a `Code.Proposal` the `CICD.run_testnet!/1` should start a testnet with
  few `uniris-node`s and one `uniris-validator`. The `uniris-validator` runs
  `uniris-proposal-validator` escript and gathers metrics from `uniris-node`s.
  The `uniris-proposal-validator` escript runs benchmarks and playbooks before
  and after upgrade.
  """

  alias Uniris.Governance.Code.Proposal

  use Knigge, otp_app: :uniris, default: __MODULE__.Docker

  @doc """
  Start CICD
  """
  @callback child_spec(any()) :: Supervisor.child_spec()

  @doc """
  Execute the continuous integration of the code proposal
  """
  @callback run_ci!(Proposal.t()) :: :ok

  @doc """
  Return CI log from the proposal address
  """
  @callback get_log(binary()) :: {:ok, binary()} | {:error, term}

  @doc """
  Execute the continuous delivery of the code proposal to a testnet
  """
  @callback run_testnet!(Proposal.t()) :: :ok

  @doc """
  Remove all artifacts generated during `run_ci!/1` and `run_testnet!/1`
  """
  @callback clean(address :: binary()) :: :ok
end
