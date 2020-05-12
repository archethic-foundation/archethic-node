defmodule UnirisCore.Crypto.TransactionLoader do
  @moduledoc false

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Keys
  alias UnirisCore.Storage
  alias UnirisCore.PubSub
  alias UnirisCore.Crypto
  alias UnirisCore.Utils

  require Logger

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    renewal_interval = Keyword.get(opts, :renewal_interval)

    Enum.each(Storage.node_transactions(), &load_transaction/1)

    with {:ok, tx} <- Storage.get_last_node_shared_secrets_transaction(),
         {:authorized, encrypted_key, encrypted_daily_nonce_seed} <- load_transaction(tx) do
      load_daily_nonce_seed(encrypted_daily_nonce_seed, encrypted_key)
    end

    PubSub.register_to_new_transaction()

    {:ok, %{renewal_interval: renewal_interval}}
  end

  def handle_info(
        {:new_transaction, tx = %Transaction{type: :node_shared_secrets}},
        state = %{renewal_interval: renewal_interval}
      ) do
    renewal_offset = Utils.time_offset(renewal_interval)

    case load_transaction(tx) do
      :skip ->
        {:noreply, state}

      {:authorized, encrypted_key, encrypted_daily_nonce_seed} ->
        # Schedule the loading of the daily nonce for the renewal interval
        unless !Map.has_key?(state, :ref_daily_nonce_scheduler) do
          Process.cancel_timer(state.ref_daily_nonce_scheduler)
        end

        ref_daily_nonce_scheduler =
          Process.send_after(
            self(),
            {:set_daily_nonce, encrypted_daily_nonce_seed, encrypted_key},
            renewal_offset
          )

        new_state = Map.put(state, :ref_daily_nonce_scheduler, ref_daily_nonce_scheduler)
        {:noreply, new_state}
    end
  end

  def handle_info({:new_transaction, tx = %Transaction{}}, state) do
    load_transaction(tx)
    {:noreply, state}
  end

  def handle_info({:set_daily_nonce, encrypted_daily_nonce_seed, encrypted_key}, state) do
    load_daily_nonce_seed(encrypted_daily_nonce_seed, encrypted_key)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp load_transaction(%Transaction{
         type: :node,
         previous_public_key: previous_public_key
       }) do
    previous_address = Crypto.hash(previous_public_key)

    case Storage.get_transaction(previous_address) do
      {:ok, %Transaction{previous_public_key: last_public_key}} ->
        if Crypto.node_public_key() == last_public_key do
          Crypto.increment_number_of_generate_node_keys()
          Logger.info("Node key index incremented")
        end

      {:error, :transaction_not_exists} ->
        if Crypto.node_public_key() == previous_public_key do
          Crypto.increment_number_of_generate_node_keys()
          Logger.info("Node key index incremented")
        end
    end
  end

  defp load_transaction(%Transaction{
         type: :node_shared_secrets,
         data: %TransactionData{
           keys: %Keys{
             secret: secret,
             authorized_keys: authorized_keys
           }
         }
       }) do
    Crypto.increment_number_of_generate_node_shared_keys()

    case Map.get(authorized_keys, Crypto.node_public_key()) do
      nil ->
        :skip

      encrypted_key ->
        # 60 == byte size of the aes encryption of 32 byte of seed
        encrypted_daily_nonce_seed = :binary.part(secret, 0, 60)
        encrypted_transaction_seed = :binary.part(secret, 60, 60)

        Crypto.decrypt_and_set_node_shared_secrets_transaction_seed(
          encrypted_transaction_seed,
          encrypted_key
        )

        Logger.debug("Node shared secrets seed loaded")

        {:authorized, encrypted_key, encrypted_daily_nonce_seed}
    end
  end

  defp load_transaction(_tx), do: :ok

  defp load_daily_nonce_seed(encrypted_daily_nonce_seed, encrypted_key) do
    Crypto.decrypt_and_set_daily_nonce_seed(encrypted_daily_nonce_seed, encrypted_key)
    Logger.debug("Node shared secrets daily nonce updated")
  end
end
