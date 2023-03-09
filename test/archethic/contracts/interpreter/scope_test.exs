defmodule Archethic.Contracts.Interpreter.ScopeTest do
  use ArchethicCase

  alias Archethic.Contracts.Interpreter.Scope

  doctest Scope

  test "global variables" do
    Scope.init(%{"var1" => %{"prop" => 1}})
    Scope.write_at([], "var2", 2)
    assert Scope.read_global(["var1", "prop"]) == 1
    assert Scope.read_global(["var2"]) == 2
  end

  test "write_at/3" do
    Scope.init()

    hierarchy = ["depth1"]
    Scope.create(hierarchy)
    Scope.write_at(hierarchy, "var1", 1)
    assert Scope.read(hierarchy, "var1") == 1

    hierarchy = ["depth1", "depth2"]
    Scope.create(hierarchy)
    Scope.write_at(hierarchy, "var2", 2)
    assert Scope.read(hierarchy, "var2") == 2
  end

  test "write_cascade/3" do
    Scope.init()

    hierarchy1 = ["depth1"]
    Scope.create(hierarchy1)
    Scope.write_cascade(hierarchy1, "var1", 1)

    hierarchy2 = ["depth1", "depth2"]
    Scope.create(hierarchy2)
    Scope.write_cascade(hierarchy2, "var1", 2)

    assert Scope.read(hierarchy1, "var1") == 2
    assert Scope.read(hierarchy2, "var1") == 2
  end

  test "read/3" do
    Scope.init(%{"map" => %{"key" => 1}})
    assert Scope.read([], "map", "key") == 1

    hierarchy = ["xx"]
    Scope.create(hierarchy)
    Scope.write_at(hierarchy, "map2", %{"key2" => 2})
    assert Scope.read(hierarchy, "map2", "key2") == 2
  end

  test "update_global/2" do
    Scope.init(%{"transaction" => %{"content" => "cat"}})
    Scope.update_global(["transaction"], fn t -> %{t | "content" => "dog"} end)
    assert Scope.read_global(["transaction", "content"]) == "dog"
  end
end
