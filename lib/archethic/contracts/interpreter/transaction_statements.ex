defmodule ArchEthic.Contracts.Interpreter.TransactionStatements do
  @moduledoc false

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger.Transfer, as: NFTTransfer
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  @doc """
  Set the transaction type

  ## Examples

       iex> TransactionStatements.set_type(%Transaction{}, "transfer")
       %Transaction{ type: :transfer }
  """
  @spec set_type(Transaction.t(), binary()) :: Transaction.t()
  def set_type(tx = %Transaction{}, type) when type in ["transfer", "nft", "hosting"] do
    %{tx | type: String.to_existing_atom(type)}
  end

  @doc """
  Add a UCO transfer

  ## Examples

      iex> TransactionStatements.add_uco_transfer(%Transaction{data: %TransactionData{}}, [{"to", "22368B50D3B2976787CFCC27508A8E8C67483219825F998FC9D6908D54D0FE10"}, {"amount", 10.04}])
      %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %UCOTransfer{
                  to: <<34, 54, 139, 80, 211, 178, 151, 103, 135, 207, 204, 39, 80, 138, 142, 140, 103, 72, 50, 25, 130, 95, 153, 143, 201, 214, 144, 141, 84, 208, 254, 16>>,
                  amount: 10.04
                }
              ]
            }
          }
        }
      }
  """
  @spec add_uco_transfer(Transaction.t(), list()) :: Transaction.t()
  def add_uco_transfer(tx = %Transaction{}, [{"to", to}, {"amount", amount}])
      when is_binary(to) and is_float(amount) do
    update_in(
      tx,
      [Access.key(:data), Access.key(:ledger), Access.key(:uco), Access.key(:transfers)],
      &[%UCOTransfer{to: decode_binary(to), amount: amount} | &1]
    )
  end

  @doc """
  Add a NFT transfer

  ## Examples

      iex> TransactionStatements.add_nft_transfer(%Transaction{data: %TransactionData{}}, [
      ...>   {"to", "22368B50D3B2976787CFCC27508A8E8C67483219825F998FC9D6908D54D0FE10"},
      ...>   {"amount", 10.0},
      ...>   {"nft", "70541604258A94B76DB1F1AF5A2FC2BEF165F3BD9C6B7DDB3F1ACC628465E528"}
      ...> ])
      %Transaction{
        data: %TransactionData{
          ledger: %Ledger{
            nft: %NFTLedger{
              transfers: [
                %NFTTransfer{
                    to: <<34, 54, 139, 80, 211, 178, 151, 103, 135, 207, 204, 39, 80, 138, 142, 140,
                      103, 72, 50, 25, 130, 95, 153, 143, 201, 214, 144, 141, 84, 208, 254, 16>>,
                    amount: 10.0,
                    nft: <<112, 84, 22, 4, 37, 138, 148, 183, 109, 177, 241, 175, 90, 47, 194, 190, 241, 101, 243,
                      189, 156, 107, 125, 219, 63, 26, 204, 98, 132, 101, 229, 40>>
                }
              ]
            }
          }
        }
      }
  """
  @spec add_nft_transfer(Transaction.t(), list()) :: Transaction.t()
  def add_nft_transfer(tx = %Transaction{}, [{"to", to}, {"amount", amount}, {"nft", nft}])
      when is_binary(to) and is_binary(nft) and is_float(amount) do
    update_in(
      tx,
      [Access.key(:data), Access.key(:ledger), Access.key(:nft), Access.key(:transfers)],
      &[%NFTTransfer{to: decode_binary(to), amount: amount, nft: decode_binary(nft)} | &1]
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
  Add an authorized public key to read the secret with an encrypted key

  ## Examples

      iex> TransactionStatements.add_authorized_key(%Transaction{data: %TransactionData{}}, [
      ...>   {"public_key", "22368B50D3B2976787CFCC27508A8E8C67483219825F998FC9D6908D54D0FE10"},
      ...>   {"encrypted_secret_key", "FB49F76933689ECC9D260D57C2BEF9489234FE72DD2ED1C77E2E8B4E94D9137F"}
      ...> ])
      %Transaction{
        data: %TransactionData{
          keys: %Keys{
            authorized_keys: %{
              <<34, 54, 139, 80, 211, 178, 151, 103, 135, 207, 204, 39, 80, 138, 142, 140,
              103, 72, 50, 25, 130, 95, 153, 143, 201, 214, 144, 141, 84, 208, 254, 16>> =>
              <<251, 73, 247, 105, 51, 104, 158, 204, 157, 38, 13, 87, 194, 190, 249, 72, 146,
              52, 254, 114, 221, 46, 209, 199, 126, 46, 139, 78, 148, 217, 19, 127>>
            }
          }
        }
      }
  """
  @spec add_authorized_key(Transaction.t(), list()) :: map()
  def add_authorized_key(tx = %Transaction{}, [
        {"public_key", public_key},
        {"encrypted_secret_key", encrypted_secret_key}
      ])
      when is_binary(public_key) and is_binary(encrypted_secret_key) do
    update_in(
      tx,
      [Access.key(:data), Access.key(:keys), Access.key(:authorized_keys)],
      &Map.put(&1, decode_binary(public_key), decode_binary(encrypted_secret_key))
    )
  end

  @doc """
  Set the transaction encrypted secret

  ## Examples

      iex> TransactionStatements.set_secret(%Transaction{data: %TransactionData{}}, "mysecret")
      %Transaction{
        data: %TransactionData{
          keys: %Keys{
            secret: "mysecret"
          }
        }
      }
  """
  @spec set_secret(Transaction.t(), binary()) :: Transaction.t()
  def set_secret(tx = %Transaction{}, secret) when is_binary(secret) do
    put_in(
      tx,
      [Access.key(:data), Access.key(:keys), Access.key(:secret)],
      decode_binary(secret)
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
    if String.printable?(bin) do
      case Base.decode16(bin, case: :mixed) do
        {:ok, hex} ->
          hex

        _ ->
          bin
      end
    else
      bin
    end
  end
end
