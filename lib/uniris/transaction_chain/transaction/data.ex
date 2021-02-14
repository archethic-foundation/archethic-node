defmodule Uniris.TransactionChain.TransactionData do
  @moduledoc """
  Represents any transaction data block
  """
  alias Uniris.Crypto

  alias __MODULE__.Keys
  alias __MODULE__.Ledger

  defstruct recipients: [], ledger: %Ledger{}, code: "", keys: %Keys{}, content: ""

  @typedoc """
  Transaction data is composed from:
  - Recipients: list of address recipients for smart contract interactions
  - Ledger: Movement operations on UCO, NFT or Stock ledger
  - Code: Contains the smart contract code including triggers, conditions and actions
  - Keys: Map of key owners and delegations
  - Content: Free content to store any data as binary
  """
  @type t :: %__MODULE__{
          recipients: list(binary()),
          ledger: Ledger.t(),
          code: binary(),
          keys: Keys.t(),
          content: binary()
        }

  @doc ~S"""
  Serialize transaction data into binary format

  ## Examples

      iex> %TransactionData{
      ...>    code: "actions do new_transaction(:transfer) |> add_uco_transfer(to: 892B5257A038BBB14F0DD8734FA09A50F4F55E8856B72F96F2A6014EEB8A2EAB72, amount: 10.5) end",
      ...>    content: "Lorem ipsum dolor sit amet, consectetur adipiscing eli",
      ...>    keys: %Keys{
      ...>      secret: <<225, 11, 213, 74, 41, 54, 189, 139, 179, 79>>,
      ...>      authorized_keys: %{}
      ...>    },
      ...>    ledger: %Ledger{},
      ...>    recipients: [
      ...>      <<0, 98, 220, 40, 53, 113, 34, 14, 142, 121, 132, 166, 27, 147, 41, 129, 195, 168,
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
      0, 98, 220, 40, 53, 113, 34, 14, 142, 121, 132, 166, 27, 147, 41, 129, 195, 168,
      241, 217, 111, 115, 164, 99, 135, 86, 123, 17, 195, 106, 248, 173, 31
      >>
  """
  def serialize(%__MODULE__{
        code: code,
        content: content,
        keys: keys,
        ledger: ledger,
        recipients: recipients
      }) do
    <<byte_size(code)::32, code::binary, byte_size(content)::32, content::binary,
      Keys.serialize(keys)::binary, Ledger.serialize(ledger)::binary, length(recipients)::8,
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
      ...> 0, 0, 0, 10,
      ...> 225, 11, 213, 74, 41, 54, 189, 139, 179, 79,
      ...> 0,
      ...> 0,
      ...> 0,
      ...> 1,
      ...> 0, 98, 220, 40, 53, 113, 34, 14, 142, 121, 132, 166, 27, 147, 41, 129, 195, 168,
      ...> 241, 217, 111, 115, 164, 99, 135, 86, 123, 17, 195, 106, 248, 173, 31
      ...> >>
      ...> |> TransactionData.deserialize()
      {
        %TransactionData{
          code: "actions do new_transaction(:transfer) |> add_uco_transfer(to: 892B5257A038BBB14F0DD8734FA09A50F4F55E8856B72F96F2A6014EEB8A2EAB72, amount: 10.5) end",
          content: "Lorem ipsum dolor sit amet, consectetur adipiscing eli",
          keys: %Keys{
            secret: <<225, 11, 213, 74, 41, 54, 189, 139, 179, 79>>,
            authorized_keys: %{}
          },
          ledger: %Ledger{
            uco: %UCOLedger{}
          },
          recipients: [
            <<0, 98, 220, 40, 53, 113, 34, 14, 142, 121, 132, 166, 27, 147, 41, 129, 195, 168,
               241, 217, 111, 115, 164, 99, 135, 86, 123, 17, 195, 106, 248, 173, 31>>
          ]
        },
        ""
      }
  """
  def deserialize(
        <<code_size::32, code::binary-size(code_size), content_size::32,
          content::binary-size(content_size), rest::bitstring>>
      ) do
    {keys, rest} = Keys.deserialize(rest)
    {ledger, rest} = Ledger.deserialize(rest)
    <<nb_recipients::8, rest::bitstring>> = rest
    {recipients, rest} = reduce_recipients(rest, nb_recipients, [])

    {
      %__MODULE__{
        code: code,
        content: content,
        keys: keys,
        ledger: ledger,
        recipients: recipients
      },
      rest
    }
  end

  defp reduce_recipients(rest, 0, _acc), do: {[], rest}

  defp reduce_recipients(rest, nb_recipients, acc) when nb_recipients == length(acc),
    do: {Enum.reverse(acc), rest}

  defp reduce_recipients(<<hash_id::8, rest::bitstring>>, nb_recipients, acc) do
    hash_size = Crypto.hash_size(hash_id)
    <<address::binary-size(hash_size), rest::bitstring>> = rest
    reduce_recipients(rest, nb_recipients, [<<hash_id::8>> <> address | acc])
  end

  @spec from_map(map()) :: t()
  def from_map(data = %{}) do
    %__MODULE__{
      content: Map.get(data, :content, ""),
      code: Map.get(data, :code, ""),
      ledger: Map.get(data, :ledger, %Ledger{}) |> Ledger.from_map(),
      keys: Map.get(data, :keys, %Keys{}) |> Keys.from_map(),
      recipients: Map.get(data, :recipients, [])
    }
  end

  @spec to_map(t() | nil) :: map()
  def to_map(nil) do
    %{
      content: "",
      code: "",
      ledger: Ledger.to_map(nil),
      keys: Keys.to_map(nil),
      recipients: []
    }
  end

  def to_map(data = %__MODULE__{}) do
    %{
      content: Map.get(data, :content, ""),
      code: Map.get(data, :code, ""),
      ledger: data |> Map.get(:ledger) |> Ledger.to_map(),
      keys: data |> Map.get(:keys) |> Keys.to_map(),
      recipients: Map.get(data, :recipients, [])
    }
  end
end
