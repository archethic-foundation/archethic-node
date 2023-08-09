defmodule Archethic.P2P.Message.ValidateSmartContractCall do
  @moduledoc """
  Represents a message to validate a smart contract call
  """

  @enforce_keys [:contract_address, :transaction, :inputs_before]
  defstruct [:contract_address, :transaction, :inputs_before]

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Crypto
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.Utils

  @type t :: %__MODULE__{
          contract_address: binary(),
          transaction: Transaction.t(),
          inputs_before: DateTime.t()
        }

  @doc """
  Serialize message into binary

  ## Examples

      iex> %ValidateSmartContractCall{
      ...>   contract_address: <<0, 0, 25, 237, 181, 114, 105, 229, 172, 192, 56, 164, 52, 131, 240, 186, 238, 113,
      ...>     242, 175, 162, 43, 112, 219, 224, 158, 39, 212, 78, 37, 4, 37, 202, 228>>,
      ...>   transaction: %Transaction{
      ...>     version: 1,
      ...>     address: <<0, 0, 120, 135, 125, 48, 92, 13, 27, 60, 42, 84, 221, 204, 42, 196,
      ...>       25, 37, 237, 215, 122, 113, 54, 59, 9, 251, 27, 179, 5, 44, 116, 217, 180, 32>>,
      ...>     type: :data,
      ...>     data: %TransactionData{},
      ...>     origin_signature: <<163, 184, 57, 242, 100, 203, 42, 179, 241, 235, 35, 167,
      ...>       197, 56, 228, 120, 110, 122, 64, 31, 230, 231, 110, 247, 119, 139, 211, 85,
      ...>       134, 192, 125, 6, 190, 51, 118, 60, 239, 190, 15, 138, 6, 137, 87, 32, 13,
      ...>       241, 26, 186, 1, 113, 112, 58, 24, 242, 140, 245, 201, 66, 132, 213, 105,
      ...>       229, 14, 2>>,
      ...>     previous_public_key: <<0, 0, 84, 200, 174, 114, 81, 219, 237, 219, 237, 222,
      ...>       27, 55, 149, 8, 235, 248, 37, 69, 1, 8, 128, 139, 184, 80, 114, 82, 40, 61,
      ...>       25, 169, 26, 69>>,
      ...>     previous_signature: <<83, 137, 109, 48, 131, 81, 37, 65, 81, 210, 9, 87, 246,
      ...>       107, 10, 101, 24, 218, 230, 38, 212, 35, 242, 216, 223, 83, 224, 11, 168,
      ...>       158, 5, 198, 202, 48, 233, 171, 107, 127, 70, 206, 98, 145, 93, 119, 98, 58,
      ...>       79, 206, 161, 21, 251, 218, 6, 44, 55, 133, 13, 122, 125, 219, 122, 131, 73,
      ...>       6>>,
      ...>   },
      ...>   inputs_before: ~U[2023-05-23 14:22:44.414Z]
      ...> } |> ValidateSmartContractCall.serialize()
      <<
        # Contract address
        0, 0, 25, 237, 181, 114, 105, 229, 172, 192, 56, 164, 52, 131, 240, 186, 238, 113,
        242, 175, 162, 43, 112, 219, 224, 158, 39, 212, 78, 37, 4, 37, 202, 228,
        # Transaction
        0, 0, 0, 1, 0, 0, 120, 135, 125, 48, 92, 13, 27, 60, 42, 84, 221, 204, 42,
        196, 25, 37, 237, 215, 122, 113, 54, 59, 9, 251, 27, 179, 5, 44, 116, 217,
        180, 32, 250, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 84, 200,
        174, 114, 81, 219, 237, 219, 237, 222, 27, 55, 149, 8, 235, 248, 37, 69, 1, 8,
        128, 139, 184, 80, 114, 82, 40, 61, 25, 169, 26, 69, 64, 83, 137, 109, 48,
        131, 81, 37, 65, 81, 210, 9, 87, 246, 107, 10, 101, 24, 218, 230, 38, 212, 35,
        242, 216, 223, 83, 224, 11, 168, 158, 5, 198, 202, 48, 233, 171, 107, 127, 70,
        206, 98, 145, 93, 119, 98, 58, 79, 206, 161, 21, 251, 218, 6, 44, 55, 133, 13,
        122, 125, 219, 122, 131, 73, 6, 64, 163, 184, 57, 242, 100, 203, 42, 179, 241,
        235, 35, 167, 197, 56, 228, 120, 110, 122, 64, 31, 230, 231, 110, 247, 119,
        139, 211, 85, 134, 192, 125, 6, 190, 51, 118, 60, 239, 190, 15, 138, 6, 137,
        87, 32, 13, 241, 26, 186, 1, 113, 112, 58, 24, 242, 140, 245, 201, 66, 132,
        213, 105, 229, 14, 2, 0,
        # Inputs before (timestamp)
        0, 0, 1, 136, 72, 253, 172, 190
      >>
  """

  def serialize(%__MODULE__{
        contract_address: contract_address,
        transaction: tx = %Transaction{},
        inputs_before: time = %DateTime{}
      }) do
    <<contract_address::binary, Transaction.serialize(tx)::bitstring,
      DateTime.to_unix(time, :millisecond)::64>>
  end

  @doc """
  Deserialize the encoded message

  ## Examples

      iex> ValidateSmartContractCall.deserialize(<<
      ...> # Contract address
      ...> 0, 0, 25, 237, 181, 114, 105, 229, 172, 192, 56, 164, 52, 131, 240, 186, 238, 113,
      ...> 242, 175, 162, 43, 112, 219, 224, 158, 39, 212, 78, 37, 4, 37, 202, 228,
      ...> # Transaction
      ...> 0, 0, 0, 1, 0, 0, 120, 135, 125, 48, 92, 13, 27, 60, 42, 84, 221, 204, 42,
      ...> 196, 25, 37, 237, 215, 122, 113, 54, 59, 9, 251, 27, 179, 5, 44, 116, 217,
      ...> 180, 32, 250, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 84, 200,
      ...> 174, 114, 81, 219, 237, 219, 237, 222, 27, 55, 149, 8, 235, 248, 37, 69, 1, 8,
      ...> 128, 139, 184, 80, 114, 82, 40, 61, 25, 169, 26, 69, 64, 83, 137, 109, 48,
      ...> 131, 81, 37, 65, 81, 210, 9, 87, 246, 107, 10, 101, 24, 218, 230, 38, 212, 35,
      ...> 242, 216, 223, 83, 224, 11, 168, 158, 5, 198, 202, 48, 233, 171, 107, 127, 70,
      ...> 206, 98, 145, 93, 119, 98, 58, 79, 206, 161, 21, 251, 218, 6, 44, 55, 133, 13,
      ...> 122, 125, 219, 122, 131, 73, 6, 64, 163, 184, 57, 242, 100, 203, 42, 179, 241,
      ...> 235, 35, 167, 197, 56, 228, 120, 110, 122, 64, 31, 230, 231, 110, 247, 119,
      ...> 139, 211, 85, 134, 192, 125, 6, 190, 51, 118, 60, 239, 190, 15, 138, 6, 137,
      ...> 87, 32, 13, 241, 26, 186, 1, 113, 112, 58, 24, 242, 140, 245, 201, 66, 132,
      ...> 213, 105, 229, 14, 2, 0,
      ...> # Inputs before (timestamp)
      ...> 0, 0, 1, 136, 72, 253, 172, 190
      ...> >>)
      {
        %ValidateSmartContractCall{
            contract_address: <<0, 0, 25, 237, 181, 114, 105, 229, 172, 192, 56, 164, 52, 131, 240, 186, 238, 113,
              242, 175, 162, 43, 112, 219, 224, 158, 39, 212, 78, 37, 4, 37, 202, 228>>,
            transaction: %Transaction{
              version: 1,
              address: <<0, 0, 120, 135, 125, 48, 92, 13, 27, 60, 42, 84, 221, 204, 42, 196,
                25, 37, 237, 215, 122, 113, 54, 59, 9, 251, 27, 179, 5, 44, 116, 217, 180, 32>>,
              type: :data,
              data: %TransactionData{},
              origin_signature: <<163, 184, 57, 242, 100, 203, 42, 179, 241, 235, 35, 167,
                197, 56, 228, 120, 110, 122, 64, 31, 230, 231, 110, 247, 119, 139, 211, 85,
                134, 192, 125, 6, 190, 51, 118, 60, 239, 190, 15, 138, 6, 137, 87, 32, 13,
                241, 26, 186, 1, 113, 112, 58, 24, 242, 140, 245, 201, 66, 132, 213, 105,
                229, 14, 2>>,
              previous_public_key: <<0, 0, 84, 200, 174, 114, 81, 219, 237, 219, 237, 222,
                27, 55, 149, 8, 235, 248, 37, 69, 1, 8, 128, 139, 184, 80, 114, 82, 40, 61,
                25, 169, 26, 69>>,
              previous_signature: <<83, 137, 109, 48, 131, 81, 37, 65, 81, 210, 9, 87, 246,
                107, 10, 101, 24, 218, 230, 38, 212, 35, 242, 216, 223, 83, 224, 11, 168,
                158, 5, 198, 202, 48, 233, 171, 107, 127, 70, 206, 98, 145, 93, 119, 98, 58,
                79, 206, 161, 21, 251, 218, 6, 44, 55, 133, 13, 122, 125, 219, 122, 131, 73,
                6>>,
            },
            inputs_before: ~U[2023-05-23 14:22:44.414Z]
        },
        ""
      }
  """
  def deserialize(data) when is_bitstring(data) do
    {contract_address, rest} = Utils.deserialize_address(data)
    {tx, <<timestamp::64, rest::bitstring>>} = Transaction.deserialize(rest)

    {
      %__MODULE__{
        contract_address: contract_address,
        transaction: tx,
        inputs_before: DateTime.from_unix!(timestamp, :millisecond)
      },
      rest
    }
  end

  @spec process(t(), Crypto.key()) :: SmartContractCallValidation.t()
  def process(
        %__MODULE__{
          contract_address: contract_address,
          transaction: transaction = %Transaction{},
          inputs_before: datetime
        },
        _
      ) do
    # During the validation of a call there is no validation_stamp yet.
    # We need one because the contract might want to access transaction.timestamp
    # which is bound to validation_stamp.timestamp
    transaction = %Transaction{
      transaction
      | validation_stamp: ValidationStamp.generate_dummy(timestamp: datetime)
    }

    valid? =
      with {:ok, contract_tx} <- TransactionChain.get_transaction(contract_address),
           {:ok, contract} <- Contracts.from_transaction(contract_tx),
           true <-
             Contracts.valid_condition?(:transaction, contract, transaction, datetime),
           :ok <- maybe_execute_trigger(contract, transaction, time_now: datetime) do
        true
      else
        _ ->
          false
      end

    %SmartContractCallValidation{
      valid?: valid?
    }
  end

  defp maybe_execute_trigger(contract = %Contract{triggers: triggers}, transaction, opts) do
    if Map.has_key?(triggers, :transaction) do
      case Contracts.execute_trigger(:transaction, contract, transaction, nil, opts) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      :ok
    end
  end
end
