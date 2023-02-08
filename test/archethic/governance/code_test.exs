defmodule Archethic.Governance.CodeTest do
  use ExUnit.Case

  alias Archethic.Governance.Code
  alias Archethic.Governance.Code.Proposal

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

  test "valid_appup? should pass" do
    changes =
      "diff --git a/mix.exs b/mix.exs\nindex c615ed94..d16e2d6f 100644\n--- a/mix.exs\n+++ b/mix.exs\n@@ -4,7 +4,7 @@ defmodule Archethic.MixProject do\n   def project do\n     [\n       app: :archethic,\n-      version: \"1.0.7\",\n+      version: \"1.0.8\",\n       build_path: \"_build\",\n       config_path: \"config/config.exs\",\n       deps_path: \"deps\",\ndiff --git a/rel/appups/archethic/1.0.7_to_1.0.8.appup b/rel/appups/archethic/1.0.7_to_1.0.8.appup\nnew file mode 100644\nindex 00000000..0f18b8e1\n--- /dev/null\n+++ b/rel/appups/archethic/1.0.7_to_1.0.8.appup\n@@ -0,0 +1,4 @@\n+{\"1.0.8\",\n+ [{\"1.0.7\",\n+   [{load_module,'TOTO', []}]}]\n+}.\n\\ No newline at end of file"

    current_version = "1.0.7"
    version = "1.0.8"

    assert Code.valid_appup?(changes, version, current_version)
  end

  test "valid_appup? should fail because appup contains illegal instruction" do
    changes =
      "diff --git a/mix.exs b/mix.exs\nindex c615ed94..d16e2d6f 100644\n--- a/mix.exs\n+++ b/mix.exs\n@@ -4,7 +4,7 @@ defmodule Archethic.MixProject do\n   def project do\n     [\n       app: :archethic,\n-      version: \"1.0.7\",\n+      version: \"1.0.8\",\n       build_path: \"_build\",\n       config_path: \"config/config.exs\",\n       deps_path: \"deps\",\ndiff --git a/rel/appups/archethic/1.0.7_to_1.0.8.appup b/rel/appups/archethic/1.0.7_to_1.0.8.appup\nnew file mode 100644\nindex 00000000..0f18b8e1\n--- /dev/null\n+++ b/rel/appups/archethic/1.0.7_to_1.0.8.appup\n@@ -0,0 +1,4 @@\n+{\"1.0.8\",\n+ [{\"1.0.7\",\n+   [{load_module_toto,'TOTO', []}]}]\n+}.\n\\ No newline at end of file"

    current_version = "1.0.7"
    version = "1.0.8"

    refute Code.valid_appup?(changes, version, current_version)
  end

  test "valid_appup? should fail because appup contains wrong version" do
    changes =
      "diff --git a/mix.exs b/mix.exs\nindex c615ed94..d16e2d6f 100644\n--- a/mix.exs\n+++ b/mix.exs\n@@ -4,7 +4,7 @@ defmodule Archethic.MixProject do\n   def project do\n     [\n       app: :archethic,\n-      version: \"1.0.7\",\n+      version: \"1.0.8\",\n       build_path: \"_build\",\n       config_path: \"config/config.exs\",\n       deps_path: \"deps\",\ndiff --git a/rel/appups/archethic/1.0.7_to_1.0.8.appup b/rel/appups/archethic/1.0.7_to_1.0.8.appup\nnew file mode 100644\nindex 00000000..0f18b8e1\n--- /dev/null\n+++ b/rel/appups/archethic/1.0.7_to_1.0.8.appup\n@@ -0,0 +1,4 @@\n+{\"1.0.9\",\n+ [{\"1.0.7\",\n+   [{load_module_toto,'TOTO', []}]}]\n+}.\n\\ No newline at end of file"

    current_version = "1.0.7"
    version = "1.0.8"

    refute Code.valid_appup?(changes, version, current_version)
  end

  test "valid_appup? should fail because it doens't contain appup" do
    changes =
      "diff --git a/mix.exs b/mix.exs\nindex c615ed94..d16e2d6f 100644\n--- a/mix.exs\n+++ b/mix.exs\n@@ -4,7 +4,7 @@ defmodule Archethic.MixProject do\n   def project do\n     [\n       app: :archethic,\n-      version: \"1.0.7\",\n+      version: \"1.0.8\",\n       build_path: \"_build\",\n       config_path: \"config/config.exs\",\n       deps_path: \"deps\",\n"

    current_version = "1.0.7"
    version = "1.0.8"

    refute Code.valid_appup?(changes, version, current_version)
  end

  doctest Code
end
