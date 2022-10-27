defmodule ArchethicWeb.API.Schema.OriginPublicKey do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset
  @max_certificate_size_limit_in_bytes 9057
  @supported_curve_bin [0, 1, 2]
  @supported_origin_bin [0, 1, 2]

  alias ArchethicWeb.API.Types.{Hex, PublicKey}

  alias Archethic.{Crypto, SharedSecrets}

  embedded_schema do
    field(:origin_public_key, PublicKey)
    field(:certificate, Hex)
  end

  def changeset(params = %{}) do
    %__MODULE__{}
    |> cast(params, [:certificate, :origin_public_key])
    |> validate_required([:origin_public_key], trim: true)
    |> validate_origin_public_key()
    |> validate_length(:certificate,
      count: :bytes,
      max: @max_certificate_size_limit_in_bytes,
      message: "Certificate size exceeds limit"
    )
    |> validate_certificate()
    |> inject_empty_certificate()
  end

  defp inject_empty_certificate(changeset = %Ecto.Changeset{changes: changes}) do
    case Map.get(changes, :certificate) do
      nil ->
        Ecto.Changeset.change(changeset, certificate: "")

      _ ->
        changeset
    end
  end

  defp validate_origin_public_key(changeset = %Ecto.Changeset{}) do
    validate_change(changeset, :origin_public_key, fn :origin_public_key, origin_public_key ->
      <<curve_id::8, origin_id::8, _public_key_bin::binary>> = origin_public_key
      supported_origin_bin = @supported_origin_bin
      supported_curve_bin = @supported_curve_bin

      with {:curve_id, true} <- {:curve_id, curve_id in supported_curve_bin},
           {:origin_id, true} <- {:origin_id, origin_id in supported_origin_bin},
           false <- SharedSecrets.has_origin_public_key?(origin_public_key) do
        []
      else
        {:curve_id, false} ->
          [{:origin_public_key, "Invalid Curve #{curve_id}"}]

        {:origin_id, false} ->
          [{:origin_public_key, "Invalid Origin #{origin_id}"}]

        true ->
          # exisiting tx with the origin public key
          [{:origin_public_key, "Already Exists"}]
      end
    end)
  end

  defp validate_certificate(changeset = %Ecto.Changeset{valid?: false}), do: changeset

  defp validate_certificate(
         changeset = %Ecto.Changeset{changes: %{origin_public_key: origin_public_key}}
       ) do
    validate_change(changeset, :certificate, fn :certificate, certificate ->
      case valid_certificate?(origin_public_key, certificate) do
        {:ok, :valid} ->
          []

        :error ->
          [{:certificate, "Invalid Certificate"}]
      end
    end)
  end

  @spec valid_certificate?(origin_public_key :: Crypto.key(), certificate :: binary) ::
          :error | {:ok, :valid}
  def valid_certificate?(origin_public_key, certificate) do
    with root_ca_public_key <-
           Crypto.get_root_ca_public_key(origin_public_key),
         true <-
           Crypto.verify_key_certificate?(origin_public_key, certificate, root_ca_public_key) do
      {:ok, :valid}
    else
      _ -> :error
    end
  end
end
