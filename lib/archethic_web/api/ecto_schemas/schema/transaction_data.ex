defmodule ArchethicWeb.API.Schema.TransactionData do
  @moduledoc false
  @content_max_size Application.compile_env!(:archethic, :transaction_data_content_max_size)
  @code_max_size Application.compile_env!(:archethic, :transaction_data_code_max_size)

  use Ecto.Schema
  import Ecto.Changeset

  alias Archethic.Crypto
  alias ArchethicWeb.API.Schema.Ledger
  alias ArchethicWeb.API.Schema.Ownership
  alias ArchethicWeb.API.Types.Hex

  embedded_schema do
    field(:code, :string)
    field(:content, Hex)
    embeds_one(:ledger, Ledger)
    embeds_many(:ownerships, Ownership)
    field(:recipients, {:array, :any})
  end

  def changeset(changeset = %__MODULE__{}, params) do
    case maybe_cast_recipients(params) do
      {:error, reason} ->
        changeset
        |> cast(params, [:recipients])
        |> Ecto.Changeset.add_error(:recipients, reason)

      {:ok, params} ->
        changeset
        |> cast(params, [:code, :content, :recipients])
        |> cast_embed(:ledger)
        |> cast_embed(:ownerships)
        |> validate_length(:content,
          max: @content_max_size,
          message: "content size must be less than content_max_size",
          count: :bytes
        )
        |> validate_length(:code,
          max: @code_max_size,
          message: "code size can't be more than #{Integer.to_string(@code_max_size)} bytes",
          count: :bytes
        )
        |> validate_length(:ownerships, max: 255, message: "ownerships can not be more that 255")
        |> validate_length(:recipients,
          max: 255,
          message: "maximum number of recipients can be 255"
        )
    end
  end

  # recipients is a list of either binary or map
  # so we can't use ecto to cast this value
  defp maybe_cast_recipients(params = %{"recipients" => recipients}) do
    recipients =
      Enum.map(recipients, fn
        recipient = %{"address" => address_hex} ->
          action = Map.get(recipient, "action")
          args = Map.get(recipient, "args")

          if action == "", do: throw(:invalid_format)
          if action == nil && args != nil, do: throw(:invalid_format)

          %{
            address:
              case decode_address(address_hex) do
                {:ok, address} ->
                  address

                {:error, reason} ->
                  throw(reason)
              end,
            action: action,
            args: args
          }

        # legacy, transaction version 1
        address_hex when is_binary(address_hex) ->
          %{
            address:
              case decode_address(address_hex) do
                {:ok, address} ->
                  address

                {:error, reason} ->
                  throw(reason)
              end,
            action: nil,
            args: nil
          }
      end)

    {:ok, %{params | "recipients" => recipients}}
  rescue
    FunctionClauseError ->
      {:error, "invalid recipient format"}
  catch
    :invalid_format ->
      {:error, "invalid recipient format"}

    :invalid_address ->
      {:error, "invalid hash"}

    :invalid_hex ->
      {:error, "must be hexadecimal"}
  end

  defp maybe_cast_recipients(params), do: {:ok, params}

  defp decode_address(address_hex) do
    case Base.decode16(address_hex, case: :mixed) do
      {:ok, bin} ->
        if Crypto.valid_address?(bin) do
          {:ok, bin}
        else
          {:error, :invalid_address}
        end

      :error ->
        {:error, :invalid_hex}
    end
  end
end
