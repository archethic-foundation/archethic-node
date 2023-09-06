defmodule Archethic.Contracts.Interpreter.ScopeTest do
  use ArchethicCase

  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.Scope
  alias Archethic.Contracts.Interpreter.FunctionInterpreter
  alias Archethic.Contracts.Interpreter.FunctionKeys

  doctest Scope

  describe "create_context/0" do
    test "should create empty context to existing scope" do
      Process.put(:scope, %{"context_list" => [], "var1" => %{"prop" => 1}, "var2" => 4})

      Scope.create_context()

      assert %{"context_list" => [context_ref]} = Process.get(:scope)

      assert %{
               "context_list" => [context_ref],
               "var1" => %{"prop" => 1},
               "var2" => 4,
               context_ref => %{
                 "scope_hierarchy" => []
               }
             } == Process.get(:scope)
    end

    test "should create new context if one already exists" do
      # create scope with existing context
      Process.put(:scope, %{
        "context_list" => ["context_1"],
        "var1" => %{"prop" => 1},
        "var2" => 4,
        "context_1" => %{
          "scope_hierarchy" => []
        }
      })

      Scope.create_context()

      assert %{"context_list" => [context_ref_2, _]} = Process.get(:scope)

      assert %{
               "context_list" => [context_ref_2, "context_1"],
               "var1" => %{"prop" => 1},
               "var2" => 4,
               "context_1" => %{
                 "scope_hierarchy" => []
               },
               context_ref_2 => %{
                 "scope_hierarchy" => []
               }
             } == Process.get(:scope)
    end
  end

  describe "leave_context/0" do
    test "should remove the only existing context" do
      Process.put(:scope, %{
        "context_list" => ["context_1"],
        "var1" => %{"prop" => 1},
        "var2" => 4,
        "context_1" => %{
          "scope_hierarchy" => []
        }
      })

      Scope.leave_context()

      assert %{
               "context_list" => [],
               "var1" => %{"prop" => 1},
               "var2" => 4
             } == Process.get(:scope)
    end

    test "should remove the current context when multiple contexts exist" do
      Process.put(:scope, %{
        "context_list" => ["context_1", "context_2"],
        "var1" => %{"prop" => 1},
        "var2" => 4,
        "context_1" => %{
          "scope_hierarchy" => []
        },
        "context_2" => %{
          "scope_hierarchy" => []
        }
      })

      Scope.leave_context()

      assert %{
               "context_list" => ["context_2"],
               "var1" => %{"prop" => 1},
               "var2" => 4,
               "context_2" => %{
                 "scope_hierarchy" => []
               }
             } == Process.get(:scope)
    end
  end

  describe "create/0" do
    test "should create scope in current context" do
      scope = %{
        "context_list" => ["current_context", "other_context"],
        "var1" => %{"prop" => 1},
        "var2" => 4,
        "current_context" => %{
          "scope_hierarchy" => []
        },
        "other_context" => %{
          "scope_hierarchy" => []
        }
      }

      Process.put(:scope, scope)

      Scope.create()

      assert %{
               "current_context" => %{
                 "scope_hierarchy" => [scope_ref]
               }
             } = Process.get(:scope)

      assert %{
               "context_list" => ["current_context", "other_context"],
               "var1" => %{"prop" => 1},
               "var2" => 4,
               "current_context" => %{
                 "scope_hierarchy" => [scope_ref],
                 scope_ref => %{}
               },
               "other_context" => %{
                 "scope_hierarchy" => []
               }
             } == Process.get(:scope)
    end

    test "should add another scope to an existing context hierarchy, inside current scope" do
      # Setup with an existing scope in the current context
      scope = %{
        "context_list" => ["current_context"],
        "current_context" => %{
          "scope_hierarchy" => ["first_scope", "second_scope"],
          "first_scope" => %{
            "second_scope" => %{}
          }
        }
      }

      Process.put(:scope, scope)

      Scope.create()

      assert %{
               "current_context" => %{
                 "scope_hierarchy" => ["first_scope", "second_scope", new_scope_ref]
               }
             } = Process.get(:scope)

      assert %{
               "context_list" => ["current_context"],
               "current_context" => %{
                 "scope_hierarchy" => ["first_scope", "second_scope", new_scope_ref],
                 "first_scope" => %{
                   "second_scope" => %{
                     new_scope_ref => %{}
                   }
                 }
               }
             } == Process.get(:scope)
    end
  end

  describe "leave_scope/0" do
    test "should remove the last scope from the scope_hierarchy and delete the corresponding map" do
      # Setup with a context that has two scopes
      scope = %{
        "context_list" => ["current_context"],
        "current_context" => %{
          "scope_hierarchy" => ["first_scope", "second_scope"],
          "first_scope" => %{
            "second_scope" => %{}
          }
        }
      }

      Process.put(:scope, scope)

      Scope.leave_scope()

      assert %{
               "context_list" => ["current_context"],
               "current_context" => %{
                 "scope_hierarchy" => ["first_scope"],
                 "first_scope" => %{}
               }
             } == Process.get(:scope)
    end

    test "should handle removing the only scope from the scope_hierarchy correctly" do
      # Setup with a context that has one scope
      scope = %{
        "context_list" => ["current_context"],
        "current_context" => %{
          "scope_hierarchy" => ["only_scope"],
          "only_scope" => %{}
        }
      }

      Process.put(:scope, scope)

      Scope.leave_scope()

      assert %{
               "context_list" => ["current_context"],
               "current_context" => %{
                 "scope_hierarchy" => []
               }
             } == Process.get(:scope)
    end
  end

  describe "write_at/2" do
    test "should write a variable in the current scope of the current context" do
      # Setup with a single context and a single scope
      scope = %{
        "context_list" => ["current_context"],
        "current_context" => %{
          "scope_hierarchy" => ["only_scope"],
          "only_scope" => %{}
        }
      }

      Process.put(:scope, scope)

      Scope.write_at("my_var", 42)

      assert %{
               "context_list" => ["current_context"],
               "current_context" => %{
                 "scope_hierarchy" => ["only_scope"],
                 "only_scope" => %{
                   "my_var" => 42
                 }
               }
             } == Process.get(:scope)
    end

    test "should write a variable in the most nested scope" do
      # Setup with a single context but multiple scopes
      scope = %{
        "context_list" => ["current_context"],
        "current_context" => %{
          "scope_hierarchy" => ["first_scope", "second_scope"],
          "first_scope" => %{
            "second_scope" => %{}
          }
        }
      }

      Process.put(:scope, scope)

      Scope.write_at("my_var", 42)

      assert %{
               "context_list" => ["current_context"],
               "current_context" => %{
                 "scope_hierarchy" => ["first_scope", "second_scope"],
                 "first_scope" => %{
                   "second_scope" => %{
                     "my_var" => 42
                   }
                 }
               }
             } == Process.get(:scope)
    end

    test "should correctly write in the current scope the current context" do
      # Setup with multiple contexts
      scope = %{
        "context_list" => ["current_context", "other_context"],
        "current_context" => %{
          "scope_hierarchy" => ["my_scope"],
          "my_scope" => %{}
        },
        "other_context" => %{
          "scope_hierarchy" => []
        }
      }

      Process.put(:scope, scope)

      Scope.write_at("my_var", 42)

      assert %{
               "context_list" => ["current_context", "other_context"],
               "current_context" => %{
                 "scope_hierarchy" => ["my_scope"],
                 "my_scope" => %{
                   "my_var" => 42
                 }
               },
               "other_context" => %{
                 "scope_hierarchy" => []
               }
             } == Process.get(:scope)
    end
  end

  describe "write_cascade/2" do
    test "should write the variable in the current scope if it doesn't exist anywhere" do
      scope = %{
        "context_list" => ["current_context"],
        "current_context" => %{
          "scope_hierarchy" => ["only_scope"],
          "only_scope" => %{}
        }
      }

      Process.put(:scope, scope)

      Scope.write_cascade("my_var", 42)

      assert %{
               "context_list" => ["current_context"],
               "current_context" => %{
                 "scope_hierarchy" => ["only_scope"],
                 "only_scope" => %{
                   "my_var" => 42
                 }
               }
             } == Process.get(:scope)
    end

    test "should be able to write value where current value is nil" do
      scope = %{
        "context_list" => ["current_context"],
        "current_context" => %{
          "scope_hierarchy" => ["first_scope", "second_scope"],
          "first_scope" => %{
            "my_var" => nil,
            "second_scope" => %{
              "another_var" => 99
            }
          }
        }
      }

      Process.put(:scope, scope)

      Scope.write_cascade("my_var", 42)

      assert %{
               "context_list" => ["current_context"],
               "current_context" => %{
                 "scope_hierarchy" => ["first_scope", "second_scope"],
                 "first_scope" => %{
                   "my_var" => 42,
                   "second_scope" => %{
                     "another_var" => 99
                   }
                 }
               }
             } == Process.get(:scope)
    end

    test "should overwrite the variable in the closest parent scope" do
      scope = %{
        "context_list" => ["current_context"],
        "current_context" => %{
          "scope_hierarchy" => ["first_scope", "second_scope"],
          "first_scope" => %{
            "my_var" => 24,
            "second_scope" => %{
              "another_var" => 99
            }
          }
        }
      }

      Process.put(:scope, scope)

      Scope.write_cascade("my_var", 42)

      assert %{
               "context_list" => ["current_context"],
               "current_context" => %{
                 "scope_hierarchy" => ["first_scope", "second_scope"],
                 "first_scope" => %{
                   "my_var" => 42,
                   "second_scope" => %{
                     "another_var" => 99
                   }
                 }
               }
             } == Process.get(:scope)
    end

    test "should not overwrite protected global variable" do
      scope = %{
        "context_list" => ["current_context"],
        :im_protected => 123,
        "current_context" => %{
          "scope_hierarchy" => ["first_scope", "second_scope"],
          "first_scope" => %{
            "my_var" => 24,
            "second_scope" => %{
              "another_var" => 99
            }
          }
        }
      }

      Process.put(:scope, scope)

      Scope.write_cascade("im_protected", 42)

      assert %{
               "context_list" => ["current_context"],
               :im_protected => 123,
               "current_context" => %{
                 "scope_hierarchy" => ["first_scope", "second_scope"],
                 "first_scope" => %{
                   "my_var" => 24,
                   "second_scope" => %{
                     "another_var" => 99,
                     "im_protected" => 42
                   }
                 }
               }
             } == Process.get(:scope)
    end

    test "should correctly overwrite variable in closest parent scope among multiple parent scopes" do
      scope = %{
        "context_list" => ["current_context"],
        "current_context" => %{
          "scope_hierarchy" => ["parent_scope", "child_scope", "grandchild_scope"],
          "parent_scope" => %{
            "my_var" => 11,
            "child_scope" => %{
              "my_var" => 24,
              "grandchild_scope" => %{}
            }
          }
        }
      }

      Process.put(:scope, scope)

      Scope.write_cascade("my_var", 42)

      assert %{
               "context_list" => ["current_context"],
               "current_context" => %{
                 "scope_hierarchy" => ["parent_scope", "child_scope", "grandchild_scope"],
                 "parent_scope" => %{
                   "my_var" => 11,
                   "child_scope" => %{
                     "my_var" => 42,
                     "grandchild_scope" => %{}
                   }
                 }
               }
             } == Process.get(:scope)
    end

    test "should overwrite global variable at the root level of scope" do
      scope = %{
        "context_list" => ["current_context"],
        "current_context" => %{
          "scope_hierarchy" => []
        },
        "global_var" => 55
      }

      Process.put(:scope, scope)

      Scope.write_cascade("global_var", 100)

      assert %{
               "context_list" => ["current_context"],
               "current_context" => %{
                 "scope_hierarchy" => []
               },
               "global_var" => 100
             } == Process.get(:scope)
    end
  end

  describe "read/1" do
    test "should read a variable from the current context's deepest scope" do
      # Initial scope setup with nested scopes and contexts
      scope = %{
        "context_list" => ["current_context"],
        "global_var" => "global_value",
        "current_context" => %{
          "scope_hierarchy" => ["first_scope", "second_scope"],
          "first_scope" => %{
            "var_in_first" => "value_in_first",
            "second_scope" => %{
              "var_in_second" => "value_in_second"
            }
          }
        }
      }

      Process.put(:scope, scope)

      assert "value_in_second" == Scope.read("var_in_second")
      assert "value_in_first" == Scope.read("var_in_first")
    end

    test "should read a variable from the current context when multiple contexts exist" do
      # Initial scope setup with nested scopes and multiple contexts
      scope = %{
        "context_list" => ["current_context", "another_context"],
        "global_var" => "global_value",
        "current_context" => %{
          "scope_hierarchy" => ["current_first_scope"],
          "current_first_scope" => %{
            "var_in_current" => "value_in_current"
          }
        },
        "another_context" => %{
          "scope_hierarchy" => ["another_first_scope"],
          "another_first_scope" => %{
            "var_in_another" => "value_in_another"
          }
        }
      }

      Process.put(:scope, scope)

      assert "value_in_current" == Scope.read("var_in_current")
      assert nil == Scope.read("var_in_another")
    end

    test "should cascade until the global scope when variable not found in context's scope" do
      scope = %{
        "context_list" => ["current_context"],
        "global_var" => "global_value",
        "current_context" => %{
          "scope_hierarchy" => ["only_scope"],
          "only_scope" => %{}
        }
      }

      Process.put(:scope, scope)

      assert "global_value" == Scope.read("global_var")
    end

    test "should not be able to read protected global variables" do
      scope = %{
        "context_list" => ["current_context"],
        :time_now => 123,
        "global_var" => "global_value",
        "current_context" => %{
          "scope_hierarchy" => ["only_scope"],
          "only_scope" => %{}
        }
      }

      Process.put(:scope, scope)

      assert nil == Scope.read("time_now")
    end

    test "should return nil if variable not found even in the global scope" do
      scope = %{
        "context_list" => ["current_context"],
        "current_context" => %{
          "scope_hierarchy" => ["only_scope"],
          "only_scope" => %{}
        }
      }

      Process.put(:scope, scope)

      assert nil == Scope.read("non_existing_var")
    end
  end

  describe "read/2" do
    test "should read a map's property from the current context's scope when multiple contexts exist" do
      # Initial scope setup with nested scopes and multiple contexts
      scope = %{
        "context_list" => ["current_context", "another_context"],
        "global_map" => %{"global_key" => "global_value"},
        "current_context" => %{
          "scope_hierarchy" => ["current_first_scope", "current_second_scope"],
          "current_first_scope" => %{
            "map_in_current" => %{"key_in_current" => "value_in_current"},
            "current_second_scope" => %{
              "another_map" => %{"another_key" => "another_value"}
            }
          }
        },
        "another_context" => %{
          "scope_hierarchy" => ["another_first_scope"],
          "another_first_scope" => %{
            "map_in_another" => %{"key_in_another" => "value_in_another"}
          }
        }
      }

      Process.put(:scope, scope)

      assert "value_in_current" == Scope.read("map_in_current", "key_in_current")
      assert "another_value" == Scope.read("another_map", "another_key")
      assert nil == Scope.read("map_in_another", "key_in_another")
    end
  end

  describe "update_global/2" do
    test "should update a nested property of a global variable using the provided function" do
      scope = %{
        "transaction" => %{
          "content" => "cat"
        }
      }

      Process.put(:scope, scope)

      Scope.update_global(["transaction"], fn t -> %{t | "content" => "dog"} end)

      assert %{
               "transaction" => %{
                 "content" => "dog"
               }
             } == Process.get(:scope)
    end
  end

  describe "read_global/1" do
    test "should read a global variable using the provided path" do
      scope = %{
        "user" => %{
          "name" => "Alice"
        },
        "transaction" => "TX_001"
      }

      Process.put(:scope, scope)

      assert "Alice" == Scope.read_global(["user", "name"])
      assert "TX_001" == Scope.read_global(["transaction"])
    end
  end

  describe "execute/2" do
    test "should execute ast and return correct value" do
      ast =
        quote do
          1 + 1
        end

      assert Scope.execute(ast, %{}) == 2
    end

    test "should be able to read global variables" do
      ast =
        quote do
          var = Scope.read("my_var")
          var + 1
        end

      assert Scope.execute(ast, %{"my_var" => 9}) == 10
    end
  end

  describe "execute/4" do
    test "should execute ast that uses arguments (for functions, arguments become variables)" do
      ast =
        quote do
          Scope.read("a") + Scope.read("b")
        end

      assert Scope.execute(ast, %{}, ["a", "b"], [1, 2]) == 3

      ast =
        quote do
          Scope.read("contract")["address"]
        end

      assert Scope.execute(ast, %{}, ["contract"], [%{"address" => "0000ABCD..."}]) ==
               "0000ABCD..."
    end
  end

  describe "execute_function_ast/2" do
    test "should execute a function" do
      function_keys =
        FunctionKeys.new()
        |> FunctionKeys.add_private("do_something", 2)

      {:ok, code} =
        Interpreter.sanitize_code("""
        fun do_something(count, point) do
          count + point.x + point.y
        end
        """)

      {:ok, function_name, args_names, ast} = FunctionInterpreter.parse(code, function_keys)

      Scope.init(%{
        functions: %{
          {function_name, length(args_names)} => %{
            args: args_names,
            ast: ast,
            visibility: :private
          }
        }
      })

      assert Scope.execute_function_ast(function_name, [1, %{"x" => 2, "y" => 3}]) == 6
    end
  end
end
