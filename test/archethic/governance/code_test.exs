defmodule ArchEthic.Governance.CodeTest do
  use ExUnit.Case

  alias ArchEthic.Governance.Code
  alias ArchEthic.Governance.Code.Proposal

  test "list_source_files/0 should list the files from the master branch" do
    files = Code.list_source_files()
    assert ".gitignore" in files
    assert "README.md" in files
  end

  @tag infrastructure: true
  test "applicable_proposal? should succeed" do
    changes = File.read!(Path.join(__DIR__, "0001-Propose-to-ignore-file.patch"))
    assert Code.applicable_proposal?(%Proposal{changes: changes, address: "123"})
  end

  test "applicable_proposal? should fail" do
    changes = """
    this is not a proposal
    """

    assert !Code.applicable_proposal?(%Proposal{changes: changes, address: "123"})
  end

  @tag infrastructure: true
  test "status should not fail" do
    {status, _branch} = Code.status()
    assert status in [:clean, :dirty]
  end

  doctest Code
end
