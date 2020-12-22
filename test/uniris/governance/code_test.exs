defmodule Uniris.Governance.CodeTest do
  use ExUnit.Case

  alias Uniris.Governance.Code

  test "list_source_files/0 should list the files from the master branch" do
    files = Code.list_source_files()
    assert ".gitignore" in files
    assert "README.md" in files
  end

  doctest Code
end
