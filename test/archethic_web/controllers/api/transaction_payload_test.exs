defmodule ArchEthicWeb.API.TransactionPayloadTest do
  use ExUnit.Case

  alias ArchEthic.Crypto

  alias ArchEthicWeb.API.TransactionPayload

  describe "changeset/1" do
    test "should return errors if there are missing fields in the transaction schema" do
      assert %Ecto.Changeset{
               valid?: false,
               errors: [
                 data: {"can't be blank", [validation: :required]},
                 version: {"can't be blank", [validation: :required]},
                 address: {"can't be blank", [validation: :required]},
                 type: {"can't be blank", [validation: :required]},
                 previousPublicKey: {"can't be blank", [validation: :required]},
                 previousSignature: {"can't be blank", [validation: :required]},
                 originSignature: {"can't be blank", [validation: :required]}
               ]
             } = TransactionPayload.changeset(%{})
    end

    test "should return errors if the crypto primitives are invalid" do
      assert %Ecto.Changeset{
               valid?: false,
               errors: [
                 address: {"must be hexadecimal", _},
                 previousPublicKey: {"must be hexadecimal", _},
                 previousSignature: {"must be hexadecimal", _},
                 originSignature: {"must be hexadecimal", _}
               ]
             } =
               TransactionPayload.changeset(%{
                 "version" => 1,
                 "address" => "abc",
                 "type" => "transfer",
                 "data" => %{
                   "code" => "",
                   "content" => "",
                   "ledger" => %{
                     "uco" => %{
                       "transfers" => []
                     },
                     "nft" => %{
                       "transfers" => []
                     }
                   },
                   "keys" => %{},
                   "recipients" => []
                 },
                 "previousPublicKey" => "abc",
                 "previousSignature" => "abc",
                 "originSignature" => "abc"
               })
    end

    test "should return an error if the content is not in hex" do
      %Ecto.Changeset{
        valid?: false,
        changes: %{data: %{errors: errors}}
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{"content" => "hello"}
        })

      assert {"must be hexadecimal", _} = Keyword.get(errors, :content)
    end

    test "should return an error if the code is not a string" do
      %Ecto.Changeset{
        valid?: false,
        changes: %{data: %{errors: errors}}
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{"code" => 123}
        })

      assert {"is invalid", _} = Keyword.get(errors, :code)
    end

    test "should return an error if the uco ledger transfer address is invalid" do
      %Ecto.Changeset{
        valid?: false,
        changes: %{
          data: %{
            changes: %{
              ledger: %{
                changes: %{
                  uco: %{
                    changes: %{
                      transfers: [
                        %{
                          errors: errors
                        }
                      ]
                    }
                  }
                }
              }
            }
          }
        }
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{"uco" => %{"transfers" => [%{"to" => "abc", "amount" => 10.0}]}}
          }
        })

      assert {"must be hexadecimal", _} = Keyword.get(errors, :to)
    end

    test "should return an error if the uco ledger transfer amount is invalid" do
      %Ecto.Changeset{
        valid?: false,
        changes: %{
          data: %{
            changes: %{
              ledger: %{
                changes: %{
                  uco: %{
                    changes: %{
                      transfers: [
                        %{
                          errors: errors
                        }
                      ]
                    }
                  }
                }
              }
            }
          }
        }
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{
              "uco" => %{
                "transfers" => [
                  %{
                    "to" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "amount" => "abc"
                  }
                ]
              }
            }
          }
        })

      assert {"is invalid", _} = Keyword.get(errors, :amount)
    end

    test "should return an error if the nft ledger transfer address is invalid" do
      %Ecto.Changeset{
        valid?: false,
        changes: %{
          data: %{
            changes: %{
              ledger: %{
                changes: %{
                  nft: %{
                    changes: %{
                      transfers: [
                        %{
                          errors: errors
                        }
                      ]
                    }
                  }
                }
              }
            }
          }
        }
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{
              "nft" => %{
                "transfers" => [
                  %{
                    "to" => "abc",
                    "amount" => 10.0,
                    "nft" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>)
                  }
                ]
              }
            }
          }
        })

      assert {"must be hexadecimal", _} = Keyword.get(errors, :to)
    end

    test "should return an error if the nft ledger transfer amount is invalid" do
      %Ecto.Changeset{
        valid?: false,
        changes: %{
          data: %{
            changes: %{
              ledger: %{
                changes: %{
                  nft: %{
                    changes: %{
                      transfers: [
                        %{
                          errors: errors
                        }
                      ]
                    }
                  }
                }
              }
            }
          }
        }
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{
              "nft" => %{
                "transfers" => [
                  %{
                    "to" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "amount" => "abc",
                    "nft" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>)
                  }
                ]
              }
            }
          }
        })

      assert {"is invalid", _} = Keyword.get(errors, :amount)
    end

    test "should return an error if the nft ledger transfer nft address is invalid" do
      %Ecto.Changeset{
        valid?: false,
        changes: %{
          data: %{
            changes: %{
              ledger: %{
                changes: %{
                  nft: %{
                    changes: %{
                      transfers: [
                        %{
                          errors: errors
                        }
                      ]
                    }
                  }
                }
              }
            }
          }
        }
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{
              "nft" => %{
                "transfers" => [
                  %{
                    "to" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "amount" => 10.0,
                    "nft" => "abc"
                  }
                ]
              }
            }
          }
        })

      assert {"must be hexadecimal", _} = Keyword.get(errors, :nft)
    end

    test "should return an error if the encrypted secret is not an hexadecimal" do
      %Ecto.Changeset{
        valid?: false,
        changes: %{
          data: %{
            changes: %{
              keys: %{
                errors: errors
              }
            }
          }
        }
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "keys" => %{
              "secret" => "abc"
            }
          }
        })

      assert {"must be hexadecimal", _} = Keyword.get(errors, :secret)
    end

    test "should return an error if the public key in the authorized keys is not valid" do
      %Ecto.Changeset{
        valid?: false,
        changes: %{
          data: %{
            changes: %{
              keys: %{
                errors: errors
              }
            }
          }
        }
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "keys" => %{
              "authorizedKeys" => %{
                "key" => "hello"
              }
            }
          }
        })

      assert {"public key must be hexadecimal", _} = Keyword.get(errors, :authorizedKeys)

      %Ecto.Changeset{
        valid?: false,
        changes: %{
          data: %{
            changes: %{
              keys: %{
                errors: errors
              }
            }
          }
        }
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "keys" => %{
              "authorizedKeys" =>
                Map.put(%{}, Base.encode16(:crypto.strong_rand_bytes(32)), "hello")
            }
          }
        })

      assert {"public key is invalid", _} = Keyword.get(errors, :authorizedKeys)
    end

    test "should return an error if the encrypted key in the authorized keys is not valid" do
      %Ecto.Changeset{
        valid?: false,
        changes: %{
          data: %{
            changes: %{
              keys: %{
                errors: errors
              }
            }
          }
        }
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "keys" => %{
              "authorizedKeys" =>
                Map.put(
                  %{},
                  Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                  "hello"
                )
            }
          }
        })

      assert {"encrypted key must be hexadecimal", _} = Keyword.get(errors, :authorizedKeys)
    end

    test "should return an error if the recipients are invalid" do
      %Ecto.Changeset{
        valid?: false,
        changes: %{
          data: %{
            errors: errors
          }
        }
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "recipients" => ["hello"]
          }
        })

      {"must be hexadecimal", _} = Keyword.get(errors, :recipients)

      %Ecto.Changeset{
        valid?: false,
        changes: %{
          data: %{
            errors: errors
          }
        }
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "recipients" => [Base.encode16(:crypto.strong_rand_bytes(32))]
          }
        })

      {"invalid hash", _} = Keyword.get(errors, :recipients)
    end
  end

  test "to_map/1 should return a map of the changeset" do
    address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    previous_public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    previous_signature = :crypto.strong_rand_bytes(64)
    origin_signature = :crypto.strong_rand_bytes(64)
    recipient = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    uco_to = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    aes_key = :crypto.strong_rand_bytes(32)
    secret = Crypto.aes_encrypt("hello", aes_key)

    {authorized_public_key, _} = Crypto.generate_deterministic_keypair("seed")
    encrypted_key = Crypto.ec_encrypt(aes_key, authorized_public_key)

    assert %{
             version: 1,
             address: address,
             type: "transfer",
             previous_public_key: previous_public_key,
             previous_signature: previous_signature,
             origin_signature: origin_signature,
             data: %{
               recipients: [recipient],
               ledger: %{
                 uco: %{
                   transfers: [
                     %{to: uco_to, amount: 10.2}
                   ]
                 }
               },
               keys: %{
                 secret: secret,
                 authorized_keys: %{
                   authorized_public_key => encrypted_key
                 }
               }
             }
           } ==
             TransactionPayload.changeset(%{
               "version" => 1,
               "address" => Base.encode16(address),
               "type" => "transfer",
               "previousPublicKey" => Base.encode16(previous_public_key),
               "previousSignature" => Base.encode16(previous_signature),
               "originSignature" => Base.encode16(origin_signature),
               "data" => %{
                 "ledger" => %{
                   "uco" => %{
                     "transfers" => [
                       %{"to" => Base.encode16(uco_to), "amount" => 10.2}
                     ]
                   }
                 },
                 "keys" => %{
                   "secret" => Base.encode16(secret),
                   "authorizedKeys" =>
                     Map.put(
                       %{},
                       Base.encode16(authorized_public_key),
                       Base.encode16(encrypted_key)
                     )
                 },
                 "recipients" => [Base.encode16(recipient)]
               }
             })
             |> TransactionPayload.to_map()
  end
end
