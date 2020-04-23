defmodule UnirisCore.SharedSecrets.TransactionLoader do
  @moduledoc false

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.SharedSecrets
  alias UnirisCore.PubSub
  alias UnirisCore.P2P.Node
  alias UnirisCore.Crypto

  require Logger

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    PubSub.register_to_new_transaction()

    renewal_interval =
      :uniris_core
      |> Application.get_env(UnirisCore.SharedSecrets.NodeRenewal)
      |> Keyword.fetch!(:interval)

    # TODO: when the origin key renewal implemented , load from the storage the origin shared secrets transactions

    {:ok, %{renewal_interval: renewal_interval}}
  end

  def handle_info(
        {:new_transaction,
         %Transaction{
           type: :node_shared_secrets,
           timestamp: timestamp,
           data: %TransactionData{
             keys: %{
               daily_nonce_seed: encrypted_daily_nonce_seed,
               transaction_seed: encrypted_transaction_seed,
               authorized_keys: authorized_keys
             }
           }
         }},
        state = %{renewal_interval: renewal_interval}
      ) do
    Crypto.increment_number_of_generate_node_shared_keys()
    IO.inspect "#{Crypto.number_of_node_shared_secrets_keys()}"

    # Schedule the set of authorized nodes at the renewal interval
    Process.send_after(
      self(),
      {:authorize_nodes, Map.keys(authorized_keys)},
      get_renewal_offset(renewal_interval)
    )

    case Map.get(authorized_keys, Crypto.node_public_key()) do
      nil ->
        {:noreply, state}

      encrypted_key ->
        Crypto.decrypt_and_set_node_shared_secrets_transaction_seed(
          encrypted_transaction_seed,
          encrypted_key
        )

        Logger.info("Node shared secrets seed loaded")

        # Schedule the loading of the daily nonce for the renewal interval
        Process.send_after(
          self(),
          {:set_daily_nonce, encrypted_daily_nonce_seed, encrypted_key},
          get_renewal_offset(renewal_interval)
        )

        {:noreply, state}
    end
  end

  def handle_info(
        {:new_transaction,
         %Transaction{
           type: :origin_shared_secrets,
           data: %{content: content}
         }},
        state
      ) do
    content
    |> extract_origin_public_keys_from_content
    |> Enum.each(fn {family, keys} ->
      Enum.each(keys, &SharedSecrets.add_origin_public_key(family, &1))
    end)

    {:noreply, state}
  end

  def handle_info({:set_daily_nonce, encrypted_daily_nonce_seed, encrypted_key}, state) do
    Crypto.decrypt_and_set_daily_nonce_seed(encrypted_daily_nonce_seed, encrypted_key)
    Logger.info("Node shared secrets daily nonce updated")
    {:noreply, state}
  end

  def handle_info({:authorize_nodes, nodes}, state) do
    Enum.each(nodes, &Node.authorize/1)
    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  defp get_renewal_offset(renewal_interval) do
    current_time = Time.utc_now().second * 1000
    last_interval = renewal_interval * trunc(current_time / renewal_interval)
    next_interval = last_interval + renewal_interval
    next_interval - current_time
  end

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
