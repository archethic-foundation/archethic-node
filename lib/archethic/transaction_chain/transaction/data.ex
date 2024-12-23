defmodule Archethic.TransactionChain.TransactionData do
  @moduledoc """
  Represents any transaction data block
  """

  alias Archethic.TransactionChain.Transaction

  alias __MODULE__.Contract
  alias __MODULE__.Ledger
  alias __MODULE__.Ownership
  alias __MODULE__.Recipient

  alias Archethic.Utils.VarInt

  defstruct recipients: [],
            ledger: %Ledger{},
            code: "",
            ownerships: [],
            content: "",
            contract: nil

  @typedoc """
  Transaction data is composed from:
  - Recipients: list of recipients for smart contract interactions
  - Ledger: Movement operations on UCO TOKEN or Stock ledger
  - Code: Contains the smart contract code including triggers, conditions and actions
  - Contract: Contains the webassembly smart contract code and its manifest
  - Ownerships: List of the authorizations and delegations to proof ownership of secrets
  - Content: Free content to store any data as binary
  """
  @type t :: %__MODULE__{
          recipients: list(Recipient.t()),
          ledger: Ledger.t(),
          code: binary(),
          contract: nil | Contract.t(),
          ownerships: list(Ownership.t()),
          content: binary()
        }

  @code_max_size Application.compile_env!(:archethic, :transaction_data_code_max_size)

  @spec compress_code(String.t()) :: binary()
  def compress_code(""), do: ""

  def compress_code(code) do
    :zlib.zip(code)
  end

  @spec decompress_code(binary()) :: String.t()
  def decompress_code(""), do: ""

  def decompress_code(code) do
    :zlib.unzip(code)
  end

  @spec code_size_valid?(code :: binary(), compressed :: boolean()) :: boolean()
  def code_size_valid?(code, compressed? \\ true) do
    if compressed? do
      code |> byte_size() < @code_max_size
    else
      compress_code(code) |> byte_size() < @code_max_size
    end
  end

  @doc """
  Serialize transaction data into binary format
  """
  @spec serialize(
          tx_data :: t(),
          tx_version :: pos_integer(),
          serialization_mode :: Transaction.serialization_mode()
        ) :: bitstring()
  def serialize(
        data = %__MODULE__{
          content: content,
          ownerships: ownerships,
          ledger: ledger,
          recipients: recipients
        },
        tx_version,
        mode \\ :compact
      ) do
    ownerships_bin =
      ownerships
      |> Enum.map(&Ownership.serialize(&1, tx_version))
      |> :erlang.list_to_binary()

    recipients_bin =
      recipients
      |> Enum.map(&Recipient.serialize(&1, tx_version, mode))
      |> :erlang.list_to_bitstring()

    encoded_ownership_len = length(ownerships) |> VarInt.from_value()
    encoded_recipients_len = length(recipients) |> VarInt.from_value()

    smart_contract_binary = serialize_contract(data, tx_version, mode)

    <<smart_contract_binary::bitstring, byte_size(content)::32, content::binary,
      encoded_ownership_len::binary, ownerships_bin::binary,
      Ledger.serialize(ledger, tx_version)::binary, encoded_recipients_len::binary,
      recipients_bin::bitstring>>
  end

  defp serialize_contract(%__MODULE__{code: code}, mode, tx_version) when tx_version <= 3 do
    code =
      case mode do
        # used when msg passing
        :compact -> compress_code(code)
        # used when signing
        :extended -> code
      end

    <<byte_size(code)::32, code::binary>>
  end

  defp serialize_contract(%__MODULE__{contract: nil}, _, _), do: <<0::8>>

  defp serialize_contract(%__MODULE__{contract: contract}, tx_version, mode),
    do: <<1::8, Contract.serialize(contract, tx_version, mode)::bitstring>>

  @doc """
  Deserialize encoded transaction data
  """
  @spec deserialize(
          data :: bitstring(),
          tx_version :: pos_integer(),
          serialization_mode :: Transaction.serialization_mode()
        ) :: {t(), bitstring()}
  def deserialize(bin, tx_version, serialization_mode \\ :compact)

  def deserialize(bin, tx_version, serialization_mode) do
    {tx_data, <<content_size::32, content::binary-size(content_size), rest::bitstring>>} =
      deserialize_contract(bin, tx_version, serialization_mode)

    {nb_ownerships, rest} = VarInt.get_value(rest)

    {ownerships, rest} = reduce_ownerships(rest, nb_ownerships, [], tx_version)
    {ledger, rest} = Ledger.deserialize(rest, tx_version)

    {nb_recipients, rest} = rest |> VarInt.get_value()

    {recipients, rest} =
      reduce_recipients(rest, nb_recipients, [], tx_version, serialization_mode)

    {
      %__MODULE__{
        tx_data
        | content: content,
          ownerships: ownerships,
          ledger: ledger,
          recipients: recipients
      },
      rest
    }
  end

  defp deserialize_contract(
         <<code_size::32, code::binary-size(code_size), rest::bitstring>>,
         tx_version,
         mode
       )
       when tx_version <= 3 do
    code = if mode == :extended, do: code, else: decompress_code(code)
    {%__MODULE__{code: code}, rest}
  end

  defp deserialize_contract(<<0::8, rest::bitstring>>, _, _), do: {%__MODULE__{}, rest}

  defp deserialize_contract(<<1::8, rest::bitstring>>, tx_version, mode) do
    {contract, rest} = Contract.deserialize(rest, tx_version, mode)
    {%__MODULE__{contract: contract}, rest}
  end

  defp reduce_ownerships(rest, 0, _acc, _version), do: {[], rest}

  defp reduce_ownerships(rest, nb_ownerships, acc, _version) when nb_ownerships == length(acc),
    do: {Enum.reverse(acc), rest}

  defp reduce_ownerships(rest, nb_ownerships, acc, version) do
    {key, rest} = Ownership.deserialize(rest, version)
    reduce_ownerships(rest, nb_ownerships, [key | acc], version)
  end

  defp reduce_recipients(rest, 0, _acc, _version, _mode), do: {[], rest}

  defp reduce_recipients(rest, nb_recipients, acc, _version, _mode)
       when nb_recipients == length(acc),
       do: {Enum.reverse(acc), rest}

  defp reduce_recipients(rest, nb_recipients, acc, version, serialization_mode) do
    {recipient, rest} = Recipient.deserialize(rest, version, serialization_mode)
    reduce_recipients(rest, nb_recipients, [recipient | acc], version, serialization_mode)
  end

  @spec cast(map()) :: t()
  def cast(data = %{}) do
    code = Map.get(data, :code, "")
    code = if String.printable?(code), do: code, else: decompress_code(code)

    %__MODULE__{
      content: Map.get(data, :content, ""),
      code: code,
      contract: Map.get(data, :contract) |> Contract.cast(),
      ledger: Map.get(data, :ledger, %Ledger{}) |> Ledger.cast(),
      ownerships: Map.get(data, :ownerships, []) |> Enum.map(&Ownership.cast/1),
      recipients: Map.get(data, :recipients, []) |> Enum.map(&Recipient.cast/1)
    }
  end

  @spec to_map(t() | nil) :: map()
  def to_map(nil) do
    %{
      content: "",
      code: "",
      contract: nil,
      ledger: Ledger.to_map(nil),
      ownerships: [],
      recipients: []
    }
  end

  def to_map(%__MODULE__{
        content: content,
        code: code,
        contract: contract,
        ledger: ledger,
        ownerships: ownerships,
        recipients: recipients
      }) do
    %{
      content: content,
      code: code,
      contract: Contract.to_map(contract),
      ledger: Ledger.to_map(ledger),
      ownerships: Enum.map(ownerships, &Ownership.to_map/1),
      recipients: Enum.map(recipients, &Recipient.to_address/1),
      action_recipients: Enum.map(recipients, &Recipient.to_map/1)
    }
  end
end
