defmodule ArchethicWeb.API.TransactionPayloadTest do
  use ExUnit.Case

  alias Archethic.Crypto

  alias ArchethicWeb.API.TransactionPayload

  alias Ecto.Changeset

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
                   "ownerships" => [],
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
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
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

    test "should return an error if the content size is greater than content max size" do
      content = Base.encode16(:crypto.strong_rand_bytes(4 * 1024 * 1024))

      %Ecto.Changeset{
        valid?: false,
        changes: %{data: %{errors: errors}}
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{"content" => content}
        })

      assert {"content size must be lessthan content_max_size", _} = Keyword.get(errors, :content)
    end

    test "should return an error if the code is not a string" do
      %Ecto.Changeset{
        valid?: false,
        changes: %{data: %{errors: errors}}
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
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

    test "should return an error if the code length is more than 5 MB" do
      %Ecto.Changeset{
        valid?: false,
        changes: %{data: %{errors: errors}}
      } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{"code" => Base.encode16(:crypto.strong_rand_bytes(5 * 1024 * 1024 + 1))}
        })

      {error_message, _} = Keyword.get(errors, :code)
      assert String.starts_with?(error_message, "code size can't be more than ")
    end

    test "should return an error if the uco ledger transfer address is invalid" do
      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
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

      assert [%{to: ["must be hexadecimal"]}] =
               changeset
               |> get_errors()
               |> get_in([:data, :ledger, :uco, :transfers])
    end

    test "should return an error if the uco ledger transfer amount is invalid" do
      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
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
                    "to" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "amount" => "abc"
                  }
                ]
              }
            }
          }
        })

      assert [%{amount: ["is invalid"]}] =
               changeset |> get_errors() |> get_in([:data, :ledger, :uco, :transfers])
    end

    # Add test for uco's here
    test "should return an error if the uco ledger transfers are more than 256" do
      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{
              "uco" => %{
                "transfers" =>
                  1..257
                  |> Enum.map(fn _ ->
                    %{
                      "to" =>
                        Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                      "amount" => Enum.random(1..100)
                    }
                  end)
              }
            }
          }
        })

      assert %{transfers: ["maximum uco transfers in a transaction can be 256"]} =
               changeset |> get_errors() |> get_in([:data, :ledger, :uco])
    end

    test "should return an error if the nft ledger transfer address is invalid" do
      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
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
                    "nft" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>)
                  }
                ]
              }
            }
          }
        })

      assert [%{to: ["must be hexadecimal"]}] =
               changeset |> get_errors() |> get_in([:data, :ledger, :nft, :transfers])
    end

    test "should return an error if the nft ledger transfer amount is invalid" do
      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
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
                    "to" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "amount" => "abc",
                    "nft" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>)
                  }
                ]
              }
            }
          }
        })

      assert [
               %{
                 amount: [
                   "is invalid"
                 ]
               }
             ] = changeset |> get_errors |> get_in([:data, :ledger, :nft, :transfers])
    end

    test "should return an error if the nft ledger transfer nft address is invalid" do
      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
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
                    "to" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "amount" => 10.0,
                    "nft" => "abc"
                  }
                ]
              }
            }
          }
        })

      assert [%{nft: ["must be hexadecimal"]}] =
               changeset |> get_errors |> get_in([:data, :ledger, :nft, :transfers])
    end

    test "should return an error if the nft ledger transfers are more than 256" do
      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ledger" => %{
              "nft" => %{
                "transfers" =>
                  1..257
                  |> Enum.map(fn _ ->
                    %{
                      "to" =>
                        Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                      "amount" => Enum.random(1..100),
                      "nft" =>
                        Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>)
                    }
                  end)
              }
            }
          }
        })

      assert %{transfers: ["maximum nft transfers in a transaction can be 256"]} =
               changeset |> get_errors |> get_in([:data, :ledger, :nft])
    end

    test "should return an error if the encrypted secret is not an hexadecimal" do
      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ownerships" => [
              %{"secret" => "abc"}
            ]
          }
        })

      assert [%{secret: ["must be hexadecimal"]}] =
               changeset |> get_errors |> get_in([:data, :ownerships])
    end

    test "should return an error if the public key in the authorized keys is not valid" do
      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ownerships" => [
              %{
                "authorizedKeys" => [
                  %{
                    "publicKey" => "key",
                    "encryptedSecretKey" => "hello"
                  }
                ]
              }
            ]
          }
        })

      assert [
               %{
                 authorizedKeys: [
                   %{
                     publicKey: ["must be hexadecimal"],
                     encryptedSecretKey: ["must be hexadecimal"]
                   }
                 ]
               }
             ] = changeset |> get_errors |> get_in([:data, :ownerships])

      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ownerships" => [
              %{
                "authorizedKeys" => [
                  %{
                    "publicKey" => Base.encode16(:crypto.strong_rand_bytes(32)),
                    "encryptedSecretKey" => "hello"
                  }
                ]
              }
            ]
          }
        })

      assert [
               %{
                 authorizedKeys: [
                   %{publicKey: ["invalid key size"], encryptedSecretKey: ["must be hexadecimal"]}
                 ]
               }
             ] = changeset |> get_errors |> get_in([:data, :ownerships])
    end

    test "should return an error if the encrypted key in the authorized keys is not valid" do
      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "type" => "transfer",
          "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
          "previousPublicKey" =>
            Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
          "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
          "data" => %{
            "ownerships" => [
              %{
                "authorizedKeys" => [
                  %{
                    "publicKey" =>
                      Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                    "encryptedSecretKey" => "hello"
                  }
                ]
              }
            ]
          }
        })

      assert [%{authorizedKeys: [%{encryptedSecretKey: ["must be hexadecimal"]}]}] =
               changeset |> get_errors |> get_in([:data, :ownerships])
    end

    test "should return an error if the recipients are invalid" do
      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
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

      assert ["must be hexadecimal"] = changeset |> get_errors() |> get_in([:data, :recipients])

      changeset =
        %Ecto.Changeset{
          valid?: false
        } =
        TransactionPayload.changeset(%{
          "version" => 1,
          "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
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

      assert ["invalid hash"] = changeset |> get_errors() |> get_in([:data, :recipients])
    end
  end

  test "should return an error if the recipients are more that 256" do
    changeset =
      %Ecto.Changeset{
        valid?: false
      } =
      TransactionPayload.changeset(%{
        "version" => 1,
        "address" => Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" =>
          Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "recipients" =>
            1..257
            |> Enum.map(fn _ ->
              Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>)
            end)
        }
      })

    assert ["maximum number of recipients can be 256"] =
             changeset |> get_errors() |> get_in([:data, :recipients])
  end

  test "to_map/1 should return a map of the changeset" do
    address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    previous_public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    previous_signature = :crypto.strong_rand_bytes(64)
    origin_signature = :crypto.strong_rand_bytes(64)
    recipient = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    uco_to = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
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
                     %{to: uco_to, amount: 1_020_000_000}
                   ]
                 }
               },
               ownerships: [
                 %{
                   secret: secret,
                   authorized_keys: %{
                     authorized_public_key => encrypted_key
                   }
                 }
               ]
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
                       %{"to" => Base.encode16(uco_to), "amount" => 1_020_000_000}
                     ]
                   }
                 },
                 "ownerships" => [
                   %{
                     "secret" => Base.encode16(secret),
                     "authorizedKeys" => [
                       %{
                         "publicKey" => Base.encode16(authorized_public_key),
                         "encryptedSecretKey" => Base.encode16(encrypted_key)
                       }
                     ]
                   }
                 ],
                 "recipients" => [Base.encode16(recipient)]
               }
             })
             |> TransactionPayload.to_map()
  end

  defp get_errors(changeset) do
    Changeset.traverse_errors(changeset, fn {msg, _} ->
      msg
    end)
  end
end
