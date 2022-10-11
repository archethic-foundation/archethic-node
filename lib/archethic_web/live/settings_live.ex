defmodule ArchethicWeb.SettingsLive do
  @moduledoc false

  use ArchethicWeb, :live_view

  alias Archethic.Crypto

  alias Archethic.PubSub

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Reward

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer

  @ip_validate_regex ~r/(^127\.)|(^192\.168\.)/

  def mount(_params, %{"remote_ip" => remote_ip}, socket) do
    # Only authorized the page in the node's private network
    private_ip? =
      Regex.match?(
        @ip_validate_regex,
        :inet.ntoa(remote_ip) |> to_string()
      )

    new_socket =
      socket
      |> assign(:allowed, private_ip?)
      |> assign(:reward_address, "")
      |> assign(:error, nil)
      |> assign(:sending, false)
      |> assign(:notification, "")

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

  def handle_event("validate", %{"reward_address" => reward_address}, socket) do
    with {:ok, reward_address_bin} <- Base.decode16(reward_address, case: :mixed),
         true <- Crypto.valid_address?(reward_address_bin) do
      {:noreply, assign(socket, :error, nil)}
    else
      _ ->
        {:noreply, assign(socket, :error, "Invalid address")}
    end
  end

  def handle_info({:new_transaction, tx_address, :node, _}, socket) do
    %Node{reward_address: reward_address} = P2P.get_node_info()

    new_socket =
      socket
      |> assign(:sending, false)
      |> assign(:reward_address, Base.encode16(reward_address))
      |> assign(:notification, "Change applied!")

    PubSub.unregister_to_new_transaction_by_address(tx_address)

    {:noreply, new_socket}
  end

  def render(assigns) do
    ~L"""
    <%= if @notification != "" do %>
      <div class="notification is-success is-light" x-data="{ open: true }" x-init="() => { setTimeout(() => open = false, 3000)}" x-show="open">
      <button class="delete"></button>
      <%= @notification %>
    </div>
    <% end %>
    <div class="box">
      <div class="columns">
        <div class="column">
          <h1 class="subtitle is-5">Node's settings</h1>
        </div>
      </div>

      <form class="columns" phx-submit="save" phx-change="validate">
        <div class="column is-5-desktop">
          <div class="field">
            <label class="label">Reward's address</label>
            <div class="control">
              <input class="input <%= if @error, do: 'is-danger'%>" type="text" placeholder="Enter your new reward address" value="<%= @reward_address %>" name="reward_address" />
            </div>
            <p class="help is-danger"><%= @error %></p>
          </div>

          <div class="field">
            <div class="control">
              <%= if @sending do %>
                <button class="button is-link is-loading" disabled>Save</button>
              <% else %>
                <button class="button is-link">Save</submit>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp send_new_transaction(next_reward_address) do
    %Node{
      ip: ip,
      port: port,
      http_port: http_port,
      transport: transport,
      reward_address: previous_reward_address
    } = P2P.get_node_info()

    token_transfers = get_token_transfers(previous_reward_address, next_reward_address)

    tx =
      Transaction.new(:node, %TransactionData{
        ledger: %Ledger{
          token: %TokenLedger{
            transfers: token_transfers
          }
        },
        code: """
          condition inherit: [
            # We need to ensure the type stays consistent
            type: node,
          
            # Content and token transfers will be validated during tx's validation
            content: true,
            token_transfers: true
          ]
        """,
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

    PubSub.register_to_new_transaction_by_address(tx.address)

    Archethic.send_new_transaction(tx)
  end

  defp get_token_transfers(previous_reward_address, next_reward_address) do
    {:ok, last_address} = Archethic.get_last_transaction_address(previous_reward_address)
    {:ok, %{token: tokens}} = Archethic.get_balance(last_address)

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
