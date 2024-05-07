defmodule ArchethicWeb.Explorer.SettingsLive do
  @moduledoc false

  use ArchethicWeb.Explorer, :live_view

  alias Archethic.Crypto

  alias Archethic.Mining.Error

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Reward

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer

  alias ArchethicWeb.TransactionSubscriber

  @ip_validate_regex ~r/(^127\.)|(^192\.168\.)/

  def mount(_params, %{"remote_ip" => remote_ip}, socket) do
    # Only authorized the page in the node's private network
    ip =
      case remote_ip do
        {_, _, _, _} ->
          :inet.ntoa(remote_ip) |> to_string()

        _ ->
          :inet.ipv4_mapped_ipv6_address(remote_ip)
          |> :inet.ntoa()
          |> to_string()
      end

    private_ip? = Regex.match?(@ip_validate_regex, ip)

    new_socket =
      socket
      |> assign(:allowed, private_ip?)
      |> assign(:reward_address, "")
      |> assign(:error, nil)
      |> assign(:sending, false)
      |> assign(:notification, "")
      |> assign(:notification_data, "")
      |> assign(:notification_status, "")

    {:ok, new_socket}
  end

  def handle_params(_params, _uri, socket = %{assigns: %{allowed: true}}) do
    %Node{reward_address: reward_address} = P2P.get_node_info()
    {:noreply, assign(socket, :reward_address, Base.encode16(reward_address))}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_redirect(socket, to: "/", replace: true)}
  end

  def handle_event(
        "save",
        %{"reward_address" => reward_address},
        socket = %{assigns: %{error: nil, reward_address: previous_reward_address}}
      ) do
    if previous_reward_address != reward_address do
      send_new_transaction(Base.decode16!(reward_address, case: :mixed))
      {:noreply, assign(socket, :sending, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("noop-tx", _, socket) do
    send_noop_transaction()
    {:noreply, assign(socket, :sending, true)}
  end

  def handle_event("validate", %{"reward_address" => reward_address}, socket) do
    with {:ok, reward_address_bin} <- Base.decode16(reward_address, case: :mixed),
         true <- Crypto.valid_address?(reward_address_bin) do
      {:noreply, assign(socket, :error, nil)}
    else
      _ ->
        {:noreply, assign(socket, :error, "Invalid address")}
    end
  end

  def handle_info({:new_transaction, tx_address}, socket) do
    %Node{reward_address: reward_address} = P2P.get_node_info()

    new_socket =
      socket
      |> assign(:sending, false)
      |> assign(:reward_address, Base.encode16(reward_address))
      |> assign(:notification, "Change applied!")
      |> assign(:notification_data, Base.encode16(tx_address))
      |> assign(:notification_status, "success")

    {:noreply, new_socket}
  end

  def handle_info({:transaction_error, _address, %Error{message: message}}, socket) do
    new_socket =
      socket
      |> assign(:sending, false)
      |> assign(:notification, "Transaction is invalid - #{message}")
      |> assign(:notification_data, "")
      |> assign(:notification_status, "error")

    {:noreply, new_socket}
  end

  defp send_new_transaction(next_reward_address) do
    %Node{
      ip: ip,
      port: port,
      http_port: http_port,
      transport: transport,
      reward_address: previous_reward_address
    } = P2P.get_node_info()

    genesis_address = Crypto.first_node_public_key() |> Crypto.derive_address()

    token_transfers =
      case genesis_address do
        ^previous_reward_address ->
          get_token_transfers(previous_reward_address, next_reward_address)

        _ ->
          []
      end

    {:ok, %Transaction{data: %TransactionData{code: code}}} =
      TransactionChain.get_last_transaction(genesis_address, data: [:code])

    tx =
      Transaction.new(:node, %TransactionData{
        ledger: %Ledger{
          token: %TokenLedger{
            transfers: token_transfers
          }
        },
        code: code,
        content:
          Node.encode_transaction_content(
            ip,
            port,
            http_port,
            transport,
            next_reward_address,
            Crypto.origin_node_public_key(),
            Crypto.get_key_certificate(Crypto.origin_node_public_key())
          )
      })

    TransactionSubscriber.register(tx.address, System.monotonic_time())

    Archethic.send_new_transaction(tx, forward?: true)
  end

  defp send_noop_transaction() do
    %Node{
      ip: ip,
      port: port,
      http_port: http_port,
      transport: transport,
      reward_address: reward_address
    } = P2P.get_node_info()

    genesis_address = Crypto.first_node_public_key() |> Crypto.derive_address()

    {:ok, %Transaction{data: %TransactionData{code: code}}} =
      TransactionChain.get_last_transaction(genesis_address, data: [:code])

    tx =
      Transaction.new(:node, %TransactionData{
        code: code,
        content:
          Node.encode_transaction_content(
            ip,
            port,
            http_port,
            transport,
            reward_address,
            Crypto.origin_node_public_key(),
            Crypto.get_key_certificate(Crypto.origin_node_public_key())
          )
      })

    TransactionSubscriber.register(tx.address, System.monotonic_time())

    Archethic.send_new_transaction(tx, forward?: true)
  end

  defp get_token_transfers(previous_reward_address, next_reward_address) do
    {:ok, genesis_address} = Archethic.fetch_genesis_address(previous_reward_address)
    %{token: tokens} = Archethic.get_balance(genesis_address)

    tokens
    |> Enum.filter(fn {{address, _}, _} -> Reward.is_reward_token?(address) end)
    |> Enum.map(fn {{address, token_id}, amount} ->
      %TokenTransfer{
        to: next_reward_address,
        amount: amount,
        token_id: token_id,
        token_address: address
      }
    end)
  end
end
