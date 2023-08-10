defmodule ModuleExample do
  use Archethic.Tag

  @tag [:io]
  def im_io(), do: :nothing
  @tag [:not_io]
  def im_io(_), do: im_private()

  @tag [:log]
  defdelegate print(message),
    to: IO,
    as: :inspect

  @tag [:should_not_consider]
  defp im_private(), do: :nothing
end

defmodule TagTest do
  @moduledoc false

  use ArchethicCase
  use ExUnitProperties

  describe "tags/0" do
    test "should use tags from first method declaration" do
      assert %{im_io: [:io]} = ModuleExample.tags()
    end

    test "should not consider private functions" do
      assert nil == Map.get(ModuleExample.tags(), :im_private)
    end

    test "should consider delegate functions" do
      assert %{print: [:log]} = ModuleExample.tags()
    end
  end

  describe "tagged_with?/2" do
    test "should return true if function is tagged with corresponding tag" do
      assert ModuleExample.tagged_with?(:print, :log)
      assert ModuleExample.tagged_with?(:im_io, :io)
    end

    test "should return false if existing function is not tagged with corresponding tag" do
      refute ModuleExample.tagged_with?(:print, :not_there)
      refute ModuleExample.tagged_with?(:im_io, :me_neither)
    end

    test "should return false if unexisting function " do
      refute ModuleExample.tagged_with?(:do_not_exist, :log)
      refute ModuleExample.tagged_with?(:not_a_function, :io)
    end
  end
end
