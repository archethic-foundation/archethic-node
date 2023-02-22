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
    current_version = "1.0.7"
    appup_version = version = "1.0.8"

    instruction = "load_module"

    changes = generate_diff(version, current_version, appup_version, instruction)

    assert Code.valid_appup?(changes, version, current_version)
  end

  test "valid_appup? should fail because appup contains illegal instruction" do
    current_version = "1.0.7"
    appup_version = version = "1.0.8"

    instruction = "invalid"

    changes = generate_diff(version, current_version, appup_version, instruction)

    refute Code.valid_appup?(changes, version, current_version)
  end

  test "valid_appup? should throw an error because appup contains illegal function calls" do
    current_version = "1.0.7"
    appup_version = version = "1.0.8"

    changes = generate_diff_with_function_call(version, current_version, appup_version)

    assert catch_throw(Code.valid_appup?(changes, version, current_version)) ==
             "Appup file contained calls to a function which is not permitted"
  end

  test "valid_appup? should fail because appup contains wrong version" do
    current_version = "1.0.7"
    version = "1.0.8"
    appup_version = "1.0.9"
    instruction = "load_module"

    changes = generate_diff(version, current_version, appup_version, instruction)

    refute Code.valid_appup?(changes, version, current_version)
  end

  test "valid_appup? should fail because it doens't contain appup" do
    current_version = "1.0.7"
    appup_version = version = "1.0.8"
    instruction = "load_module"

    changes = generate_diff(version, current_version, appup_version, instruction, false)

    refute Code.valid_appup?(changes, version, current_version)
  end

  defp generate_diff(
         version,
         current_version,
         appup_version,
         instruction,
         should_add_appup? \\ true
       ) do
    base_appup(current_version, version) <>
      maybe_add_appup(current_version, appup_version, instruction, should_add_appup?) <>
      end_base_appup()
  end

  defp generate_diff_with_function_call(
         version,
         current_version,
         appup_version
       ) do
    base_appup(current_version, version) <>
      appup_with_function_call(current_version, appup_version) <>
      end_base_appup()
  end

  defp base_appup(current_version, version) do
    "diff --git a/mix.exs b/mix.exs\n" <>
      "index c615ed94..d16e2d6f 100644\n" <>
      "--- a/mix.exs\n" <>
      "+++ b/mix.exs\n" <>
      "@@ -4,7 +4,7 @@ defmodule Archethic.MixProject do\n" <>
      "   def project do\n" <>
      "     [\n" <>
      "       app: :archethic,\n" <>
      "-      version: \"#{current_version}\",\n" <>
      "+      version: \"#{version}\",\n" <>
      "       build_path: \"_build\",\n" <>
      "       config_path: \"config/config.exs\",\n" <>
      "       deps_path: \"deps\",\n"
  end

  defp end_base_appup() do
    "\\ No newline at end of file"
  end

  defp appup_with_function_call(current_version, appup_version) do
    "diff --git a/rel/appups/archethic/1.0.7_to_1.0.8.appup b/rel/appups/archethic/1.0.7_to_1.0.8.appup\n" <>
      "new file mode 100644\n" <>
      "index 00000000..0f18b8e1\n" <>
      "--- /dev/null\n" <>
      "+++ b/rel/appups/archethic/1.0.7_to_1.0.8.appup\n" <>
      "@@ -0,0 +1,4 @@\n" <>
      "+{\"#{appup_version}\",\n" <>
      "+ [{\"#{current_version}\",\n" <>
      "+   [{load_module, io:format(\"execute some code\"), []}]}],\n" <>
      "+ [{\"#{current_version}\",\n" <>
      "+   [{load_module, 'TOTO', []}]}]\n" <>
      "+}.\n"
  end

  defp maybe_add_appup(_, _, _, false), do: ""

  defp maybe_add_appup(current_version, appup_version, instruction, true) do
    "diff --git a/rel/appups/archethic/1.0.7_to_1.0.8.appup b/rel/appups/archethic/1.0.7_to_1.0.8.appup\n" <>
      "new file mode 100644\n" <>
      "index 00000000..0f18b8e1\n" <>
      "--- /dev/null\n" <>
      "+++ b/rel/appups/archethic/1.0.7_to_1.0.8.appup\n" <>
      "@@ -0,0 +1,4 @@\n" <>
      "+{\"#{appup_version}\",\n" <>
      "+ [{\"#{current_version}\",\n" <>
      "+   [{#{instruction},'TOTO', []}]}],\n" <>
      "+ [{\"#{current_version}\",\n" <>
      "+   [{#{instruction},'TOTO', []}]}]\n" <>
      "+}.\n"
  end

  doctest Code
end
