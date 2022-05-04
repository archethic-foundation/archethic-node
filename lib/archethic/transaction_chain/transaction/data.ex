defmodule Archethic.TransactionChain.TransactionData do
  @moduledoc """
  Represents any transaction data block
  """

  alias __MODULE__.Ledger
  alias __MODULE__.Ownership

  alias Archethic.Utils

  defstruct recipients: [], ledger: %Ledger{}, code: "", ownerships: [], content: ""

  @typedoc """
  Transaction data is composed from:
  - Recipients: list of address recipients for smart contract interactions
  - Ledger: Movement operations on UCO, NFT or Stock ledger
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
  ...> |> TransactionData.serialize()
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
  1,
  # Secret size
  0, 0, 0, 10,
  # Secret
  225, 11, 213, 74, 41, 54, 189, 139, 179, 79,
  # Number of authorized keys
  0,
  # Number of UCO transfers
  0,
  # Number of NFT transfers
  0,
  # Number of recipients
  1,
  # Recipient
  0, 0, 98, 220, 40, 53, 113, 34, 14, 142, 121, 132, 166, 27, 147, 41, 129, 195, 168,
  241, 217, 111, 115, 164, 99, 135, 86, 123, 17, 195, 106, 248, 173, 31
  >>
  """
  def serialize(%__MODULE__{
        code: code,
        content: content,
        ownerships: ownerships,
        ledger: ledger,
        recipients: recipients
      }) do
    ownerships_bin = Enum.map(ownerships, &Ownership.serialize/1) |> :erlang.list_to_binary()

    <<byte_size(code)::32, code::binary, byte_size(content)::32, content::binary,
      length(ownerships)::8, ownerships_bin::binary, Ledger.serialize(ledger)::binary,
      length(recipients)::8, :erlang.list_to_binary(recipients)::binary>>
  end

  @doc """
  Deserialize encoded transaction data

  ## Examples

  iex> <<
  ...> 0, 0, 0, 147,
  ...> "actions do new_transaction(:transfer) |> add_uco_transfer(to: 892B5257A038BBB14F0DD8734FA09A50F4F55E8856B72F96F2A6014EEB8A2EAB72, amount: 10.5) end",
  ...> 0, 0, 0, 54,
  ...> "Lorem ipsum dolor sit amet, consectetur adipiscing eli",
  ...> 1, 0, 0, 0, 10,
  ...> 225, 11, 213, 74, 41, 54, 189, 139, 179, 79,
  ...> 1,
  ...> 0, 0, 229, 188, 159, 80, 100, 5, 54, 152, 137, 201, 204, 24, 22, 125, 76, 29,
  ...> 83, 14, 154, 60, 66, 69, 121, 97, 40, 215, 226, 204, 133, 54, 187, 9,
  ...> 139, 100, 20, 32, 187, 77, 56, 30, 116, 207, 34, 95, 157, 128, 208, 115, 113,
  ...> 177, 45, 9, 93, 107, 90, 254, 173, 71, 60, 181, 113, 247, 75, 151, 127, 41, 7,
  ...> 233, 227, 98, 209, 211, 97, 117, 68, 101, 59, 121, 214, 105, 225, 218, 91, 92,
  ...> 212, 162, 48, 18, 15, 181, 70, 103, 32, 141, 4, 64, 107, 93, 117, 188, 244, 7,
  ...> 224, 214, 225, 146, 44, 83, 111, 34, 239, 99,
  ...> 0,
  ...> 0,
  ...> 1,
  ...> 0, 0, 98, 220, 40, 53, 113, 34, 14, 142, 121, 132, 166, 27, 147, 41, 129, 195, 168,
  ...> 241, 217, 111, 115, 164, 99, 135, 86, 123, 17, 195, 106, 248, 173, 31
  ...> >>
  ...> |> TransactionData.deserialize()
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
  def deserialize(
        <<code_size::32, code::binary-size(code_size), content_size::32,
          content::binary-size(content_size), nb_ownerships::8, rest::bitstring>>
      ) do
    {ownerships, rest} = reduce_ownerships(rest, nb_ownerships, [])
    {ledger, rest} = Ledger.deserialize(rest)
    <<nb_recipients::8, rest::bitstring>> = rest
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

  defp reduce_ownerships(rest, 0, _acc), do: {[], rest}

  defp reduce_ownerships(rest, nb_ownerships, acc) when nb_ownerships == length(acc),
    do: {Enum.reverse(acc), rest}

  defp reduce_ownerships(rest, nb_ownerships, acc) do
    {key, rest} = Ownership.deserialize(rest)
    reduce_ownerships(rest, nb_ownerships, [key | acc])
  end

  defp reduce_recipients(rest, 0, _acc), do: {[], rest}

  defp reduce_recipients(rest, nb_recipients, acc) when nb_recipients == length(acc),
    do: {Enum.reverse(acc), rest}

  defp reduce_recipients(rest, nb_recipients, acc) do
    {recipient_address, rest} = Utils.deserialize_address(rest)
    reduce_recipients(rest, nb_recipients, [recipient_address | acc])
  end

  @spec from_map(map()) :: t()
  def from_map(data = %{}) do
    %__MODULE__{
      content: Map.get(data, :content, ""),
      code: Map.get(data, :code, ""),
      ledger: Map.get(data, :ledger, %Ledger{}) |> Ledger.from_map(),
      ownerships: Map.get(data, :ownerships, []) |> Enum.map(&Ownership.from_map/1),
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

  def to_map(data = %__MODULE__{}) do
    %{
      content: Map.get(data, :content, ""),
      code: Map.get(data, :code, ""),
      ledger: data |> Map.get(:ledger) |> Ledger.to_map(),
      ownerships: data |> Map.get(:ownerships, []) |> Enum.map(&Ownership.to_map/1),
      recipients: Map.get(data, :recipients, [])
    }
  end
end
