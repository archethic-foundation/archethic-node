defmodule Archethic.TransactionChain.TransactionData do
  @moduledoc """
  Represents any transaction data block
  """

  alias __MODULE__.Ledger
  alias __MODULE__.Ownership

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  defstruct recipients: [], ledger: %Ledger{}, code: "", ownerships: [], content: ""

  @typedoc """
  Transaction data is composed from:
  - Recipients: list of address recipients for smart contract interactions
  - Ledger: Movement operations on UCO TOKEN or Stock ledger
  - Code: Contains the smart contract code including triggers, conditions and actions
  - Ownerships: List of the authorizations and delegations to proof ownership of secrets
  - Content: Free content to store any data as binary
  """
  @type t :: %__MODULE__{
          recipients: list(binary()),
          ledger: Ledger.t(),
          code: binary(),
          ownerships: list(Ownership.t()),
          content: binary()
        }

  @doc """
  Serialize transaction data into binary format

  ## Examples

  iex> %TransactionData{
  ...>    code: "actions do new_transaction(:transfer) |> add_uco_transfer(to: 892B5257A038BBB14F0DD8734FA09A50F4F55E8856B72F96F2A6014EEB8A2EAB72, amount: 10.5) end",
  ...>    content: "Lorem ipsum dolor sit amet, consectetur adipiscing eli",
  ...>    ownerships: [%Ownership{
  ...>      secret: <<225, 11, 213, 74, 41, 54, 189, 139, 179, 79>>,
  ...>      authorized_keys: %{}
  ...>    }],
  ...>    ledger: %Ledger{},
  ...>    recipients: [
  ...>      <<0, 0, 98, 220, 40, 53, 113, 34, 14, 142, 121, 132, 166, 27, 147, 41, 129, 195, 168,
  ...>        241, 217, 111, 115, 164, 99, 135, 86, 123, 17, 195, 106, 248, 173, 31>>
  ...>    ]
  ...> }
  ...> |> TransactionData.serialize(current_transaction_version())
  <<
  # Code size
  0, 0, 0, 147,
  # Code
  "actions do new_transaction(:transfer) |> add_uco_transfer(to: 892B5257A038BBB14F0DD8734FA09A50F4F55E8856B72F96F2A6014EEB8A2EAB72, amount: 10.5) end",
  # Content size
  0, 0, 0, 54,
  # Content
  "Lorem ipsum dolor sit amet, consectetur adipiscing eli",
  # Nb ownerships
  1, 1,
  # Secret size
  0, 0, 0, 10,
  # Secret
  225, 11, 213, 74, 41, 54, 189, 139, 179, 79,
  # Number of authorized keys
  1, 0,
  # Number of UCO transfers
  1, 0,
  # Number of TOKEN transfers
  1, 0,
  # Number of recipients
  1, 1,
  # Recipient
  0, 0, 98, 220, 40, 53, 113, 34, 14, 142, 121, 132, 166, 27, 147, 41, 129, 195, 168,
  241, 217, 111, 115, 164, 99, 135, 86, 123, 17, 195, 106, 248, 173, 31
  >>
  """
  @spec serialize(tx_data :: t(), tx_version :: pos_integer()) :: bitstring()
  def serialize(
        %__MODULE__{
          code: code,
          content: content,
          ownerships: ownerships,
          ledger: ledger,
          recipients: recipients
        },
        tx_version
      ) do
    ownerships_bin =
      ownerships
      |> Enum.map(&Ownership.serialize(&1, tx_version))
      |> :erlang.list_to_binary()

    encoded_ownership_len = length(ownerships) |> VarInt.from_value()
    encoded_recipients_len = length(recipients) |> VarInt.from_value()

    <<byte_size(code)::32, code::binary, byte_size(content)::32, content::binary,
      encoded_ownership_len::binary, ownerships_bin::binary,
      Ledger.serialize(ledger, tx_version)::binary, encoded_recipients_len::binary,
      :erlang.list_to_binary(recipients)::binary>>
  end

  @doc """
  Deserialize encoded transaction data

  ## Examples

  iex> <<
  ...> 0, 0, 0, 147,
  ...> "actions do new_transaction(:transfer) |> add_uco_transfer(to: 892B5257A038BBB14F0DD8734FA09A50F4F55E8856B72F96F2A6014EEB8A2EAB72, amount: 10.5) end",
  ...> 0, 0, 0, 54,
  ...> "Lorem ipsum dolor sit amet, consectetur adipiscing eli",
  ...> 1, 1, 0, 0, 0, 10,
  ...> 225, 11, 213, 74, 41, 54, 189, 139, 179, 79,
  ...> 1, 1,
  ...> 0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
  ...> 83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9,
  ...> 139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
  ...> 177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
  ...> 233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
  ...> 212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
  ...> 224, 214, 225, 146, 44, 83, 111, 34, 239, 99,
  ...> 1, 0,
  ...> 1, 0,
  ...> 1, 1,
  ...> 0, 0, 98, 220, 40, 53, 113, 34, 14, 142, 121, 132, 166, 27, 147, 41, 129, 195, 168,
  ...> 241, 217, 111, 115, 164, 99, 135, 86, 123, 17, 195, 106, 248, 173, 31
  ...> >>
  ...> |> TransactionData.deserialize(current_transaction_version())
  {
    %TransactionData{
      code: "actions do new_transaction(:transfer) |> add_uco_transfer(to: 892B5257A038BBB14F0DD8734FA09A50F4F55E8856B72F96F2A6014EEB8A2EAB72, amount: 10.5) end",
      content: "Lorem ipsum dolor sit amet, consectetur adipiscing eli",
      ownerships: [%Ownership{
      secret: <<225, 11, 213, 74, 41, 54, 189, 139, 179, 79>>,
      authorized_keys: %{
              <<0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
              83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9>> =>
              <<139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
              177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
              233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
              212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
              224, 214, 225, 146, 44, 83, 111, 34, 239, 99>>
            }
          }],
          ledger: %Ledger{
            uco: %UCOLedger{}
          },
          recipients: [
            <<0, 0, 98, 220, 40, 53, 113, 34, 14, 142, 121, 132, 166, 27, 147, 41, 129, 195, 168,
               241, 217, 111, 115, 164, 99, 135, 86, 123, 17, 195, 106, 248, 173, 31>>
          ]
        },
        ""
      }
  """
  @spec deserialize(data :: bitstring(), tx_version :: pos_integer()) :: {t(), bitstring()}
  def deserialize(
        <<code_size::32, code::binary-size(code_size), content_size::32,
          content::binary-size(content_size), rest::bitstring>>,
        tx_version
      ) do
    {nb_ownerships, rest} = VarInt.get_value(rest)

    {ownerships, rest} = reduce_ownerships(rest, nb_ownerships, [], tx_version)
    {ledger, rest} = Ledger.deserialize(rest, tx_version)

    {nb_recipients, rest} = rest |> VarInt.get_value()
    {recipients, rest} = reduce_recipients(rest, nb_recipients, [])

    {
      %__MODULE__{
        code: code,
        content: content,
        ownerships: ownerships,
        ledger: ledger,
        recipients: recipients
      },
      rest
    }
  end

  defp reduce_ownerships(rest, 0, _acc, _version), do: {[], rest}

  defp reduce_ownerships(rest, nb_ownerships, acc, _version) when nb_ownerships == length(acc),
    do: {Enum.reverse(acc), rest}

  defp reduce_ownerships(rest, nb_ownerships, acc, version) do
    {key, rest} = Ownership.deserialize(rest, version)
    reduce_ownerships(rest, nb_ownerships, [key | acc], version)
  end

  defp reduce_recipients(rest, 0, _acc), do: {[], rest}

  defp reduce_recipients(rest, nb_recipients, acc) when nb_recipients == length(acc),
    do: {Enum.reverse(acc), rest}

  defp reduce_recipients(rest, nb_recipients, acc) do
    {recipient_address, rest} = Utils.deserialize_address(rest)
    reduce_recipients(rest, nb_recipients, [recipient_address | acc])
  end

  @spec cast(map()) :: t()
  def cast(data = %{}) do
    %__MODULE__{
      content: Map.get(data, :content, ""),
      code: Map.get(data, :code, ""),
      ledger: Map.get(data, :ledger, %Ledger{}) |> Ledger.cast(),
      ownerships: Map.get(data, :ownerships, []) |> Enum.map(&Ownership.cast/1),
      recipients: Map.get(data, :recipients, [])
    }
  end

  @spec to_map(t() | nil) :: map()
  def to_map(nil) do
    %{
      content: "",
      code: "",
      ledger: Ledger.to_map(nil),
      ownerships: [],
      recipients: []
    }
  end

  def to_map(%__MODULE__{
        content: content,
        code: code,
        ledger: ledger,
        ownerships: ownerships,
        recipients: recipients
      }) do
    %{
      content: content,
      code: code,
      ledger: Ledger.to_map(ledger),
      ownerships: Enum.map(ownerships, &Ownership.to_map/1),
      recipients: recipients
    }
  end
end
