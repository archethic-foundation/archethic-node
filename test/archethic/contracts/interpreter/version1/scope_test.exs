defmodule Archethic.Contracts.Interpreter.Version1.ScopeTest do
  use ArchethicCase

  alias Archethic.Contracts.Interpreter.Version1.Scope

  doctest Scope

  describe "where_is/3" do
    test "should return [] when variable exists at root" do
      ref1 = make_ref()
      ref2 = make_ref()

      scope = %{
        "variableName" => %{},
        ref1 => %{
          ref2 => %{}
        }
      }

      assert [] = Scope.where_is(scope, [ref1, ref2], "variableName")
    end

    test "should return current_path when no match" do
      ref1 = make_ref()
      ref2 = make_ref()

      scope = %{
        ref1 => %{
          ref2 => %{}
        }
      }

      assert [^ref1, ^ref2] = Scope.where_is(scope, [ref1, ref2], "variableName")
    end

    test "should return current_path when variable is in current scope" do
      ref1 = make_ref()
      ref2 = make_ref()

      scope = %{
        ref1 => %{
          ref2 => %{
            "variableName" => 1
          }
        }
      }

      assert [^ref1, ^ref2] = Scope.where_is(scope, [ref1, ref2], "variableName")
    end

    test "should return parent path when variable is in parent scope" do
      ref1 = make_ref()
      ref2 = make_ref()

      scope = %{
        ref1 => %{
          "variableName" => 1,
          ref2 => %{}
        }
      }

      assert [^ref1] = Scope.where_is(scope, [ref1, ref2], "variableName")
    end
  end
end
