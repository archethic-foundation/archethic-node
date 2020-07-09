defmodule UnirisCore.SharedSecrets.TransactionLoader do
  @moduledoc false

  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.PubSub

  alias UnirisCore.SharedSecrets
  alias UnirisCore.Storage

  alias UnirisCore.Transaction

  require Logger

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    PubSub.register_to_new_transaction()

    # TODO: when the origin key renewal implemented , load from the storage the origin shared secrets transactions

    Enum.each(Storage.node_transactions(), &load_transaction/1)

    {:ok, %{}}
  end

  def handle_info({:new_transaction, tx = %Transaction{}}, state) do
    load_transaction(tx)
    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  defp load_transaction(%Transaction{type: :node, previous_public_key: previous_public_key}) do
    case P2P.node_info(previous_public_key) do
      {:error, :not_found} ->
        SharedSecrets.add_origin_public_key(:software, previous_public_key)

      {:ok, %Node{first_public_key: first_public_key}}
      when first_public_key == previous_public_key ->
        SharedSecrets.add_origin_public_key(:software, previous_public_key)

      _ ->
        :ok
    end
  end

  defp load_transaction(%Transaction{type: :origin_shared_secrets, data: %{content: content}}) do
    content
    |> extract_origin_public_keys_from_content
    |> Enum.each(fn {family, keys} ->
      Enum.each(keys, &SharedSecrets.add_origin_public_key(family, &1))
    end)
  end

  defp load_transaction(_), do: :ok

  defp extract_origin_public_keys_from_content(content) do
    Regex.scan(~r/(?<=origin_public_keys:).*/, content)
    |> Enum.flat_map(& &1)
    |> List.first()
    |> case do
      nil ->
        []

      str ->
        str
        |> String.trim()
        |> String.replace("[", "")
        |> String.replace("]", "")
        |> origin_public_keys_string_to_keyword
    end
  end

  defp origin_public_keys_string_to_keyword(origin_keys_string) do
    software_keys =
      extract_origin_public_keys_from_family(
        ~r/(?<=software: ).([A-Z0-9\, ])*/,
        origin_keys_string
      )

    usb_keys =
      extract_origin_public_keys_from_family(~r/(?<=usb: ).([A-Z0-9\, ])*/, origin_keys_string)

    biometric_keys =
      extract_origin_public_keys_from_family(
        ~r/(?<=biometric: ).([A-Z0-9\, ])*/,
        origin_keys_string
      )

    [
      software: software_keys,
      usb: usb_keys,
      biometric: biometric_keys
    ]
  end

  defp extract_origin_public_keys_from_family(family_regex, origin_keys_string) do
    Regex.scan(family_regex, origin_keys_string)
    |> Enum.flat_map(& &1)
    |> List.first()
    |> case do
      nil ->
        []

      str ->
        str
        |> String.trim()
        |> String.split(",")
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(fn key ->
          key
          |> String.trim()
          |> Base.decode16!()
        end)
    end
  end
end
