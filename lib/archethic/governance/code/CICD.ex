defmodule ArchEthic.Governance.Code.CICD do
  @moduledoc ~S"""
  Provides CICD pipeline for `ArchEthic.Governance.Code.Proposal`

  The evolution of archethic-node could be represented using following stages:

    * Init - when source code is compiled into archethic-node (not covered here)
    * CI - archethic-node is verifying a proposal and generating a release upgrade
    * CD - archethic-node is forking a testnet to verify release upgrade

  In each stage a transition from a source to a result could happen

      | Stage | Source           | Transition   | Result         |
      |-------+------------------+--------------+----------------|
      | Init  | Code             | compile      | Release        |
      | CI    | Code, Proposal   | run CI tests | CiLog, Upgrade |
      | CD    | Release, Upgrade | run testnet  | TnLog, Release |

  where
    * Code - a source code of archethic-node
    * Propsal - a code proposal transaction
    * Release - a release of archethic-node
    * Upgrade - an upgrade to a release of archethic-node
    * CiLog - unit tests and type checker logs
    * TnLog - logs retrieved from running testnet fork

  ## CI
  Given a `Code.Proposal` the `CICD.run_ci!/1` should generate: a log of
  application of the `Proposal` to the `Code`, a release upgrade which is a
  delta between previous release and new release, and a new version of
  `archethic-proposal-validator` escript.

  ## CD
  Given a `Code.Proposal` the `CICD.run_testnet!/1` should start a testnet with
  few `archethic-node`s and one `archethic-validator`. The `archethic-validator` runs
  `archethic-proposal-validator` escript and gathers metrics from `archethic-node`s.
  The `archethic-proposal-validator` escript runs benchmarks and playbooks before
  and after upgrade.
  """

  alias ArchEthic.Governance.Code.Proposal

  use Knigge, otp_app: :archethic, default: __MODULE__.Docker

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
