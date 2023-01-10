defmodule Archethic.Contracts.Interpreter.TransactionStatements do
  @moduledoc false

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  @doc """
  Set the transaction type

  ## Examples

       iex> TransactionStatements.set_type(%Transaction{}, "transfer")
       %Transaction{ type: :transfer }
  """
  @spec set_type(Transaction.t(), binary()) :: Transaction.t()
  def set_type(tx = %Transaction{}, type) when type in ["transfer", "token", "hosting"] do
    %{tx | type: String.to_existing_atom(type)}
  end

  @doc """
  Add a UCO transfer

  ## Examples

      iex> TransactionStatements.add_uco_transfer(%Transaction{data: %TransactionData{}}, [{"to", "22368B50D3B2976787CFCC27508A8E8C67483219825F998FC9D6908D54D0FE10"}, {"amount", 1_040_000_000}])
      %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %UCOTransfer{
                  to: <<34, 54, 139, 80, 211, 178, 151, 103, 135, 207, 204, 39, 80, 138, 142, 140, 103, 72, 50, 25, 130, 95, 153, 143, 201, 214, 144, 141, 84, 208, 254, 16>>,
                  amount: 1_040_000_000
                }
              ]
            }
          }
        }
      }
  """
  @spec add_uco_transfer(Transaction.t(), list()) :: Transaction.t()
  def add_uco_transfer(tx = %Transaction{}, args) when is_list(args) do
    %{"to" => to, "amount" => amount} = Enum.into(args, %{})

    update_in(
      tx,
      [Access.key(:data), Access.key(:ledger), Access.key(:uco), Access.key(:transfers)],
      &[%UCOTransfer{to: decode_binary(to), amount: amount} | &1]
    )
  end

  @doc """
  Add a token transfer

  ## Examples

      iex> TransactionStatements.add_token_transfer(%Transaction{data: %TransactionData{}}, [
      ...>   {"to", "22368B50D3B2976787CFCC27508A8E8C67483219825F998FC9D6908D54D0FE10"},
      ...>   {"amount", 1_000_000_000},
      ...>   {"token_address", "70541604258A94B76DB1F1AF5A2FC2BEF165F3BD9C6B7DDB3F1ACC628465E528"},
      ...>   {"token_id",  0}
      ...> ])
      %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            token: %TokenLedger{
              transfers: [
                %TokenTransfer{
                    to: <<34, 54, 139, 80, 211, 178, 151, 103, 135, 207, 204, 39, 80, 138, 142, 140,
                      103, 72, 50, 25, 130, 95, 153, 143, 201, 214, 144, 141, 84, 208, 254, 16>>,
                    amount: 1_000_000_000,
                    token_address: <<112, 84, 22, 4, 37, 138, 148, 183, 109, 177, 241, 175, 90, 47, 194, 190, 241, 101, 243,
                      189, 156, 107, 125, 219, 63, 26, 204, 98, 132, 101, 229, 40>>,
                    token_id: 0
                }
              ]
            }
          }
        }
      }
  """
  @spec add_token_transfer(Transaction.t(), list()) :: Transaction.t()
  def add_token_transfer(tx = %Transaction{}, args) when is_list(args) do
    map_args =
      %{"to" => to, "amount" => amount, "token_address" => token_address} = Enum.into(args, %{})

    update_in(
      tx,
      [Access.key(:data), Access.key(:ledger), Access.key(:token), Access.key(:transfers)],
      &[
        %TokenTransfer{
          token_id: Map.get(map_args, "token_id", 0),
          to: decode_binary(to),
          amount: amount,
          token_address: decode_binary(token_address)
        }
        | &1
      ]
    )
  end

  @doc """
  Set transaction data content

  ## Examples

        iex> TransactionStatements.set_content(%Transaction{data: %TransactionData{}}, "hello")
        %Transaction{
          data: %TransactionData{
            content: "hello"
          }
        }
  """
  @spec set_content(Transaction.t(), binary()) :: Transaction.t()
  def set_content(tx = %Transaction{}, content) when is_binary(content) do
    put_in(tx, [Access.key(:data), Access.key(:content)], content)
  end

  def set_content(tx = %Transaction{}, content) when is_integer(content) do
    put_in(tx, [Access.key(:data), Access.key(:content)], Integer.to_string(content))
  end

  def set_content(tx = %Transaction{}, content) when is_float(content) do
    put_in(tx, [Access.key(:data), Access.key(:content)], Float.to_string(content))
  end

  @doc """
  Set transaction smart contract code

  ## Examples

      iex> TransactionStatements.set_code(%Transaction{data: %TransactionData{}}, "condition origin_family: biometric")
      %Transaction{
        data: %TransactionData{
          code: "condition origin_family: biometric"
        }
      }
  """
  @spec set_code(Transaction.t(), binary()) :: Transaction.t()
  def set_code(tx = %Transaction{}, code) when is_binary(code) do
    put_in(tx, [Access.key(:data), Access.key(:code)], code)
  end

  @doc """
  Add an ownership to add a secret with its authorized public keys

  ## Examples

      iex> %Transaction{data: %TransactionData{ownerships: [%Ownership{authorized_keys: authorized_keys}]}} = TransactionStatements.add_ownership(%Transaction{data: %TransactionData{}}, [
      ...>   {"secret", "mysecret"},
      ...>   {"secret_key", "62FE599BB217FC608D29E28C3FC4D825EA7989471261E43326FAB1A20A3C71B0"},
      ...>   {"authorized_public_keys", [
      ...>     "01000416A31DADE19AB4D9E7F22A4FA934694F265D0F20CB9D86B0B0B8FD28505CB6F9EF4D803AB5D2C49944DB0C24A12373F90A4406DBEF4577A9A59669DCAD10EBB6"
      ...>   ]}
      ...> ])
      iex> Map.keys(authorized_keys)
      [
        <<1, 0, 4, 22, 163, 29, 173, 225, 154, 180, 217, 231, 242, 42, 79, 169, 52, 105,
        79, 38, 93, 15, 32, 203, 157, 134, 176, 176, 184, 253, 40, 80, 92, 182, 249,
        239, 77, 128, 58, 181, 210, 196, 153, 68, 219, 12, 36, 161, 35, 115, 249, 10,
        68, 6, 219, 239, 69, 119, 169, 165, 150, 105, 220, 173, 16, 235, 182>>
      ]
  """
  @spec add_ownership(Transaction.t(), list()) :: Transaction.t()
  def add_ownership(tx = %Transaction{}, args) when is_list(args) do
    %{
      "secret" => secret,
      "secret_key" => secret_key,
      "authorized_public_keys" => authorized_public_keys
    } = Enum.into(args, %{})

    ownership =
      Ownership.new(
        decode_binary(secret),
        decode_binary(secret_key),
        Enum.map(authorized_public_keys, &decode_binary(&1))
      )

    update_in(
      tx,
      [Access.key(:data, %{}), Access.key(:ownerships, [])],
      &[ownership | &1]
    )
  end

  @doc """
  Add an recipient

  ## Examples

      iex> TransactionStatements.add_recipient(%Transaction{data: %TransactionData{}}, "22368B50D3B2976787CFCC27508A8E8C67483219825F998FC9D6908D54D0FE10")
      %Transaction{
        data: %TransactionData{
          recipients: [<<34, 54, 139, 80, 211, 178, 151, 103, 135, 207, 204, 39, 80, 138, 142, 140,
            103, 72, 50, 25, 130, 95, 153, 143, 201, 214, 144, 141, 84, 208, 254, 16>>]
        }
      }
  """
  @spec add_recipient(Transaction.t(), binary()) :: Transaction.t()
  def add_recipient(tx = %Transaction{}, recipient_address)
      when is_binary(recipient_address) do
    update_in(
      tx,
      [Access.key(:data), Access.key(:recipients)],
      &[decode_binary(recipient_address) | &1]
    )
  end

  defp decode_binary(bin) do
    if String.match?(bin, ~r/^[[:xdigit:]]+$/) do
      Base.decode16!(bin, case: :mixed)
    else
      bin
    end
  end
end
