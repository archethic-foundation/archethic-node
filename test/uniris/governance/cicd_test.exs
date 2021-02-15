defmodule Uniris.Governance.Code.CICD.Docker.Test do
  use ExUnit.Case

  alias Uniris.Utils

  alias Uniris.Governance.Code.CICD
  alias Uniris.Governance.Code.Proposal

  @tag :CI
  test "run_ci should succeed" do
    impl = Utils.impl(CICD)
    impl.start_link([])
    changes = File.read!(Path.join(__DIR__, "0001-CI-Pass.patch"))
    assert match?(:ok, impl.run_ci!(%Proposal{changes: changes, address: "123"}))
  end
end
