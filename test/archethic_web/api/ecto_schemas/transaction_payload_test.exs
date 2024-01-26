defmodule ArchethicWeb.API.TransactionPayloadTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Crypto

  alias ArchethicWeb.API.TransactionPayload

  alias Ecto.Changeset

  describe "changeset/1" do
    test "should return errors if params is not a map" do
      assert :error = TransactionPayload.changeset(nil)
      assert :error = TransactionPayload.changeset(1)
      assert :error = TransactionPayload.changeset("1")
    end

    test "should return errors if there are missing fields in the transaction schema" do
      assert {:ok,
              %Ecto.Changeset{
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
              }} = TransactionPayload.changeset(%{})
    end

    test "should return errors if the crypto primitives are invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => "abc",
        "type" => "transfer",
        "data" => %{
          "code" => "",
          "content" => "",
          "ledger" => %{
            "uco" => %{
              "transfers" => []
            },
            "token" => %{
              "transfers" => []
            }
          },
          "ownerships" => [],
          "recipients" => []
        },
        "previousPublicKey" => "abc",
        "previousSignature" => "abc",
        "originSignature" => "abc"
      }

      assert {:ok,
              %Ecto.Changeset{
                valid?: false,
                errors: [
                  address: {"must be hexadecimal", _},
                  previousPublicKey: {"must be hexadecimal", _},
                  previousSignature: {"must be hexadecimal", _},
                  originSignature: {"must be hexadecimal", _}
                ]
              }} = TransactionPayload.changeset(map)
    end

    test "should return an error if the content is not in hex" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{"content" => "hello"}
      }

      assert {:ok, %Ecto.Changeset{valid?: false, changes: %{data: %{errors: errors}}}} =
               TransactionPayload.changeset(map)

      assert {"must be hexadecimal", _} = Keyword.get(errors, :content)
    end

    test "should return an error if the content size is greater than content max size" do
      content = Base.encode16(:crypto.strong_rand_bytes(4 * 1024 * 1024))

      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{"content" => content}
      }

      assert {:ok, %Ecto.Changeset{valid?: false, changes: %{data: %{errors: errors}}}} =
               TransactionPayload.changeset(map)

      assert {"content size must be less than content_max_size", _} =
               Keyword.get(errors, :content)
    end

    test "should return an error if the code is not a string" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{"code" => 123}
      }

      assert {:ok, %Ecto.Changeset{valid?: false, changes: %{data: %{errors: errors}}}} =
               TransactionPayload.changeset(map)

      assert {"is invalid", _} = Keyword.get(errors, :code)
    end

    test "should return an error if the code length is more than 24KB" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{"code" => generate_code_that_exceed_limit_when_compressed()}
      }

      assert {:ok, %Ecto.Changeset{valid?: false, changes: %{data: %{errors: errors}}}} =
               TransactionPayload.changeset(map)

      assert {"Invalid transaction, code exceed max size", _} = Keyword.get(errors, :code)
    end

    test "should return an error if the uco ledger transfer address is invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{"uco" => %{"transfers" => [%{"to" => "abc", "amount" => 10.0}]}}
        }
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert [%{to: ["must be hexadecimal"]}] =
               changeset
               |> get_errors()
               |> get_in([:data, :ledger, :uco, :transfers])
    end

    test "should return an error if the uco ledger transfer amount is invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{
            "uco" => %{
              "transfers" => [
                %{
                  "to" => Base.encode16(random_address()),
                  "amount" => "abc"
                }
              ]
            }
          }
        }
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert [%{amount: ["is invalid"]}] =
               changeset |> get_errors() |> get_in([:data, :ledger, :uco, :transfers])
    end

    test "should return an error if the uco ledger transfers are more than 256" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{
            "uco" => %{
              "transfers" =>
                1..257
                |> Enum.map(fn _ ->
                  %{
                    "to" => Base.encode16(random_address()),
                    "amount" => Enum.random(1..100)
                  }
                end)
            }
          }
        }
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert %{transfers: ["maximum uco transfers in a transaction can be 256"]} =
               changeset |> get_errors() |> get_in([:data, :ledger, :uco])
    end

    test "should return an error if the token ledger transfer address is invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{
            "token" => %{
              "transfers" => [
                %{
                  "to" => "abc",
                  "amount" => 10.0,
                  "token" => Base.encode16(random_address()),
                  "tokenId" => 0
                }
              ]
            }
          }
        }
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert [%{to: ["must be hexadecimal"]}] =
               changeset |> get_errors() |> get_in([:data, :ledger, :token, :transfers])
    end

    test "should return an error if the token ledger transfer amount is invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{
            "token" => %{
              "transfers" => [
                %{
                  "to" => Base.encode16(random_address()),
                  "amount" => "abc",
                  "token" => Base.encode16(random_address()),
                  "tokenId" => 0
                }
              ]
            }
          }
        }
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert [%{amount: ["is invalid"]}] =
               changeset |> get_errors |> get_in([:data, :ledger, :token, :transfers])
    end

    test "should return an error if the token ledger transfer token address is invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{
            "token" => %{
              "transfers" => [
                %{
                  "to" => Base.encode16(random_address()),
                  "amount" => 10.0,
                  "tokenAddress" => "abc",
                  "tokenId" => 0
                }
              ]
            }
          }
        }
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert [%{tokenAddress: ["must be hexadecimal"]}] =
               changeset |> get_errors |> get_in([:data, :ledger, :token, :transfers])
    end

    test "should return an error if the token ledger transfers are more than 256" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ledger" => %{
            "token" => %{
              "transfers" =>
                1..257
                |> Enum.map(fn _ ->
                  %{
                    "to" => Base.encode16(random_address()),
                    "amount" => Enum.random(1..100),
                    "tokenAddress" => Base.encode16(random_address()),
                    "tokenId" => Enum.random(0..255)
                  }
                end)
            }
          }
        }
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert %{transfers: ["maximum token transfers in a transaction can be 256"]} =
               changeset |> get_errors |> get_in([:data, :ledger, :token])
    end

    test "should return an error if the encrypted secret is not an hexadecimal" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ownerships" => [
            %{"secret" => "abc"}
          ]
        }
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert [%{secret: ["must be hexadecimal"]}] =
               changeset |> get_errors |> get_in([:data, :ownerships])
    end

    test "should return an error if the public key in the authorized keys is not valid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
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
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

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

      map =
        put_in(map, ["data", "ownerships"], [
          %{
            "authorizedKeys" => [
              %{
                "publicKey" => Base.encode16(:crypto.strong_rand_bytes(32)),
                "encryptedSecretKey" => "hello"
              }
            ]
          }
        ])

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert [
               %{
                 authorizedKeys: [
                   %{publicKey: ["invalid key size"], encryptedSecretKey: ["must be hexadecimal"]}
                 ]
               }
             ] = changeset |> get_errors |> get_in([:data, :ownerships])
    end

    test "should return an error if the encrypted key in the authorized keys is not valid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ownerships" => [
            %{
              "authorizedKeys" => [
                %{
                  "publicKey" => Base.encode16(random_address()),
                  "encryptedSecretKey" => "hello"
                }
              ]
            }
          ]
        }
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert [%{authorizedKeys: [%{encryptedSecretKey: ["must be hexadecimal"]}]}] =
               changeset |> get_errors |> get_in([:data, :ownerships])
    end

    test "should return an error ownerships are more than 255." do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ownerships" =>
            1..256
            |> Enum.map(fn _ ->
              %{
                "authorizedKeys" =>
                  1..257
                  |> Enum.map(fn _ ->
                    %{
                      "publicKey" =>
                        Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>),
                      "encryptedSecretKey" => Base.encode16(:crypto.strong_rand_bytes(64))
                    }
                  end),
                "secret" => Base.encode16(:crypto.strong_rand_bytes(64))
              }
            end)
        }
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      {msg, _} = changeset.errors[:ownerships]
      assert "ownerships can not be more that 255" == msg
    end

    test "should return an error authorized keys in a ownership can't be more than 255" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "ownerships" => [
            %{
              "authorizedKeys" =>
                1..257
                |> Enum.map(fn _ ->
                  %{
                    "publicKey" => Base.encode16(random_address()),
                    "encryptedSecretKey" => Base.encode16(:crypto.strong_rand_bytes(64))
                  }
                end),
              "secret" => Base.encode16(:crypto.strong_rand_bytes(64))
            }
          ]
        }
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert [%{authorizedKeys: ["maximum number of authorized keys can be 255"]}] =
               changeset |> get_errors |> get_in([:data, :ownerships])
    end

    test "should return an error if the recipients are invalid" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "recipients" => [1]
        }
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert ["invalid recipient format"] =
               changeset |> get_errors() |> get_in([:data, :recipients])

      map = put_in(map, ["data", "recipients"], [%{"address" => "hello"}])

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert ["must be hexadecimal"] = changeset |> get_errors() |> get_in([:data, :recipients])

      map =
        put_in(map, ["data", "recipients"], [
          %{"address" => Base.encode16(:crypto.strong_rand_bytes(32))}
        ])

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert ["invalid hash"] = changeset |> get_errors() |> get_in([:data, :recipients])

      map =
        put_in(map, ["data", "recipients"], [
          %{"address" => "not an hexadecimal", "action" => "upgrade", "args" => []}
        ])

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert ["must be hexadecimal"] = changeset |> get_errors() |> get_in([:data, :recipients])

      map =
        put_in(map, ["data", "recipients"], [
          %{
            "address" => Base.encode16(random_address()),
            "args" => []
          }
        ])

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert ["invalid recipient format"] =
               changeset |> get_errors() |> get_in([:data, :recipients])
    end

    test "should accept recipients both named & unnamed" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "recipients" => [
            %{
              "address" => Base.encode16(random_address())
            },
            %{
              "address" => Base.encode16(random_address()),
              "action" => "something",
              "args" => []
            }
          ]
        }
      }

      assert {:ok, %Ecto.Changeset{valid?: true}} = TransactionPayload.changeset(map)
    end

    test "should return an error if the recipients are more that 255" do
      map = %{
        "version" => current_transaction_version(),
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "recipients" =>
            1..256
            |> Enum.map(fn _ ->
              %{
                "address" => Base.encode16(random_address())
              }
            end)
        }
      }

      assert {:ok, changeset} =
               {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)

      assert ["maximum number of recipients can be 255"] =
               changeset |> get_errors() |> get_in([:data, :recipients])
    end

    test "should return error if transaction V1 contains named action recipient" do
      map = %{
        "version" => 1,
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "recipients" => [
            %{
              "address" => Base.encode16(random_address()),
              "action" => "something",
              "args" => []
            }
          ]
        }
      }

      assert {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)
    end

    test "should return error if transaction V2 contains list of addresses as recipient" do
      map = %{
        "version" => 2,
        "address" => Base.encode16(random_address()),
        "type" => "transfer",
        "timestamp" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        "previousPublicKey" => Base.encode16(random_address()),
        "previousSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "originSignature" => Base.encode16(:crypto.strong_rand_bytes(64)),
        "data" => %{
          "recipients" => [Base.encode16(random_address())]
        }
      }

      assert {:ok, %Ecto.Changeset{valid?: false}} = TransactionPayload.changeset(map)
    end
  end

  test "to_map/1 should return a map of the changeset" do
    address = random_address()
    previous_public_key = random_address()
    previous_signature = :crypto.strong_rand_bytes(64)
    origin_signature = :crypto.strong_rand_bytes(64)
    recipient = random_address()
    recipient2_address = random_address()
    uco_to = random_address()
    aes_key = :crypto.strong_rand_bytes(32)
    secret = Crypto.aes_encrypt("hello", aes_key)

    {authorized_public_key, _} = Crypto.generate_deterministic_keypair("seed")
    encrypted_key = Crypto.ec_encrypt(aes_key, authorized_public_key)

    transaction_version = current_transaction_version()

    map = %{
      "version" => transaction_version,
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
        "recipients" => [
          %{"address" => Base.encode16(recipient)},
          %{
            "address" => Base.encode16(recipient2_address),
            "action" => "something",
            "args" => [1, 2, 3]
          }
        ]
      }
    }

    assert %{
             version: transaction_version,
             address: address,
             type: "transfer",
             previous_public_key: previous_public_key,
             previous_signature: previous_signature,
             origin_signature: origin_signature,
             data: %{
               recipients: [
                 %{address: recipient, action: nil, args: nil},
                 %{
                   address: recipient2_address,
                   action: "something",
                   args: [1, 2, 3]
                 }
               ],
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
           } == TransactionPayload.changeset(map) |> elem(1) |> TransactionPayload.to_map()
  end

  defp get_errors(changeset) do
    Changeset.traverse_errors(changeset, fn {msg, _} ->
      msg
    end)
  end
end
