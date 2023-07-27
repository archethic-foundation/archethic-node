defmodule Archethic.Contracts.Interpreter.ScopeTest do
  use ArchethicCase

  alias Archethic.Contracts.Interpreter.Scope

  doctest Scope

  describe "init/1" do
    test "should instantiate Scope with empty context list and global vars" do
      constants = %{"var1" => %{"prop" => 1}, "var2" => 4}
      Scope.init(constants)
      assert %{"context_list" => [], "var1" => %{"prop" => 1}, "var2" => 4} == Process.get(:scope)
    end
  end

  describe "create_context/0" do
    test "create_context/0 should create empty context to existing scope" do
      Process.put(:scope, %{"context_list" => [], "var1" => %{"prop" => 1}, "var2" => 4})

      Scope.create_context()

      %{"context_list" => [context_ref]} = Process.get(:scope)

      assert %{
               "context_list" => [^context_ref],
               "var1" => %{"prop" => 1},
               "var2" => 4,
               ^context_ref => %{
                 "scope_hierarchy" => []
               }
             } = Process.get(:scope)
    end

    test "create_context/0 should create new context if one already exists" do
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

      %{"context_list" => [context_ref_2, _]} = Process.get(:scope)

      assert %{
               "context_list" => [^context_ref_2, _],
               "var1" => %{"prop" => 1},
               "var2" => 4,
               "context_1" => %{
                 "scope_hierarchy" => []
               },
               ^context_ref_2 => %{
                 "scope_hierarchy" => []
               }
             } = Process.get(:scope)
    end
  end

  describe "leave_context/0" do
    test "leave_context/0 should remove the only existing context" do
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
             } = Process.get(:scope)
    end

    test "leave_context/0 should remove the current context when multiple contexts exist" do
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
             } = Process.get(:scope)
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

      %{
        "current_context" => %{
          "scope_hierarchy" => [scope_ref]
        }
      } = Process.get(:scope)

      assert %{
               "context_list" => ["current_context", "other_context"],
               "var1" => %{"prop" => 1},
               "var2" => 4,
               "current_context" => %{
                 "scope_hierarchy" => [^scope_ref],
                 ^scope_ref => %{}
               },
               "other_context" => %{
                 "scope_hierarchy" => []
               }
             } = Process.get(:scope)
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

      %{
        "current_context" => %{
          "scope_hierarchy" => ["first_scope", "second_scope", new_scope_ref]
        }
      } = Process.get(:scope)

      assert %{
               "context_list" => ["current_context"],
               "current_context" => %{
                 "scope_hierarchy" => ["first_scope", "second_scope", ^new_scope_ref],
                 "first_scope" => %{
                   "second_scope" => %{
                     ^new_scope_ref => %{}
                   }
                 }
               }
             } = Process.get(:scope)
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
             } = Process.get(:scope)
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
             } = Process.get(:scope)
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
             } = Process.get(:scope)
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
             } = Process.get(:scope)
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
             } = Process.get(:scope)
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
             } = Process.get(:scope)
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
             } = Process.get(:scope)
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
             } = Process.get(:scope)
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
             } = Process.get(:scope)
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

      var_value = Scope.read("var_in_second")
      assert var_value == "value_in_second"

      outer_var_value = Scope.read("var_in_first")
      assert outer_var_value == "value_in_first"
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

      var_in_current_value = Scope.read("var_in_current")
      assert var_in_current_value == "value_in_current"

      var_in_another_value = Scope.read("var_in_another")
      assert var_in_another_value == nil
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

      global_var_value = Scope.read("global_var")
      assert global_var_value == "global_value"
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

      non_existing_var_value = Scope.read("non_existing_var")
      assert non_existing_var_value == nil
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

      key_in_current_value = Scope.read("map_in_current", "key_in_current")
      assert key_in_current_value == "value_in_current"

      another_key_value = Scope.read("another_map", "another_key")
      assert another_key_value == "another_value"

      key_in_another_value = Scope.read("map_in_another", "key_in_another")
      assert key_in_another_value == nil
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
             } = Process.get(:scope)
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

      user_name = Scope.read_global(["user", "name"])
      assert user_name == "Alice"

      transaction_id = Scope.read_global(["transaction"])
      assert transaction_id == "TX_001"
    end
  end
end
