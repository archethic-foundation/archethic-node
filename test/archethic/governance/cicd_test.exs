defmodule ArchEthic.Governance.Code.CICD.Docker.Test do
  use ExUnit.Case

  alias ArchEthic.Utils

  alias ArchEthic.Governance.Code.CICD
  alias ArchEthic.Governance.Code.Proposal
  alias ArchEthic.Governance.Code.Proposal.Parser

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
