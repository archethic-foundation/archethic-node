defmodule Archethic.TransactionChain.TransactionData do
  @moduledoc """
  Represents any transaction data block
  """

  alias Archethic.TransactionChain.Transaction

  alias __MODULE__.Ledger
  alias __MODULE__.Ownership
  alias __MODULE__.Recipient

  alias Archethic.Utils.VarInt

  defstruct recipients: [], ledger: %Ledger{}, code: "", ownerships: [], content: ""

  @typedoc """
  Transaction data is composed from:
  - Recipients: list of recipients for smart contract interactions
  - Ledger: Movement operations on UCO TOKEN or Stock ledger
  - Code: Contains the smart contract code including triggers, conditions and actions
  - Ownerships: List of the authorizations and delegations to proof ownership of secrets
  - Content: Free content to store any data as binary
  """
  @type t :: %__MODULE__{
          recipients: list(Recipient.t()),
          ledger: Ledger.t(),
          code: binary(),
          ownerships: list(Ownership.t()),
          content: binary()
        }

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

  @doc """
  Serialize transaction data into binary format
  """
  @spec serialize(
          tx_data :: t(),
          tx_version :: pos_integer(),
          serialization_mode :: Transaction.serialization_mode()
        ) :: bitstring()
  def serialize(
        %__MODULE__{
          code: code,
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

    code =
      if mode == :extended do
        decompress_code(code)
      else
        code
      end

    <<byte_size(code)::32, code::binary, byte_size(content)::32, content::binary,
      encoded_ownership_len::binary, ownerships_bin::binary,
      Ledger.serialize(ledger, tx_version)::binary, encoded_recipients_len::binary,
      recipients_bin::bitstring>>
  end

  @doc """
  Deserialize encoded transaction data
  """
  @spec deserialize(
          data :: bitstring(),
          tx_version :: pos_integer(),
          serialization_mode :: Transaction.serialization_mode()
        ) :: {t(), bitstring()}
  def deserialize(
        <<code_size::32, code::binary-size(code_size), content_size::32,
          content::binary-size(content_size), rest::bitstring>>,
        tx_version,
        serialization_mode \\ :compact
      ) do
    {nb_ownerships, rest} = VarInt.get_value(rest)

    {ownerships, rest} = reduce_ownerships(rest, nb_ownerships, [], tx_version)
    {ledger, rest} = Ledger.deserialize(rest, tx_version)

    {nb_recipients, rest} = rest |> VarInt.get_value()

    {recipients, rest} =
      reduce_recipients(rest, nb_recipients, [], tx_version, serialization_mode)

    # until the migration is done, we may have both zipped and unzipped code in the database
    # may be removed in the next release
    zipped? =
      try do
        decompress_code(code)
        true
      rescue
        _ ->
          false
      end

    {
      %__MODULE__{
        code:
          if zipped? do
            code
          else
            compress_code(code)
          end,
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

  defp reduce_recipients(rest, 0, _acc, _version, _mode), do: {[], rest}

  defp reduce_recipients(rest, nb_recipients, acc, _version, _mode)
       when nb_recipients == length(acc),
       do: {Enum.reverse(acc), rest}

  defp reduce_recipients(rest, nb_recipients, acc, version, serialization_mode) do
    {recipient, rest} = Recipient.deserialize(rest, version, serialization_mode)
    reduce_recipients(rest, nb_recipients, [recipient | acc], version, serialization_mode)
  end

  @spec cast(map(), Keyword.t()) :: t()
  def cast(data = %{}, opts \\ []) do
    %__MODULE__{
      content: Map.get(data, :content, ""),
      code:
        case Keyword.get(opts, :code, :compressed) do
          :compressed ->
            Map.get(data, :code, "")

          :decompressed ->
            compress_code(Map.get(data, :code, ""))
        end,
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
      code: decompress_code(code),
      ledger: Ledger.to_map(ledger),
      ownerships: Enum.map(ownerships, &Ownership.to_map/1),
      recipients: Enum.map(recipients, &Recipient.to_address/1),
      action_recipients: Enum.map(recipients, &Recipient.to_map/1)
    }
  end
end
