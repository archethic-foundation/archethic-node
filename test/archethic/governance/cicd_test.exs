defmodule Archethic.Governance.Code.CICD.Docker.Test do
  use ExUnit.Case

  alias Archethic.Utils

  alias Archethic.Governance.Code.CICD
  alias Archethic.Governance.Code.Proposal
  alias Archethic.Governance.Code.Proposal.Parser

  @tag :CI
  test "run_ci should succeed" do
    # must run on clean working tree
    impl = Utils.impl(CICD)
    impl.start_link([])
    changes = File.read!(Path.join(__DIR__, "0001-CI-Pass.patch"))
    assert match?(:ok, impl.run_ci!(%Proposal{changes: changes, address: "123"}))
  end

  @tag :CD
  test "run_testnet should succeed" do
    # must run after "run_ci should succeed" test
    impl = Utils.impl(CICD)
    impl.start_link([])
    changes = File.read!(Path.join(__DIR__, "0001-CI-Pass.patch"))
    {:ok, version} = Parser.get_version(changes)
    proposal = %Proposal{changes: changes, address: "123", version: version}
    assert match?(:ok, impl.run_testnet!(proposal))
  end
end
