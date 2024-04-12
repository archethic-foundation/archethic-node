defmodule ArchethicWeb.Explorer.RewardsLiveTest do
  @moduledoc false
  use ArchethicCase
  use ArchethicWeb.ConnCase

  import Phoenix.{
    ConnTest,
    LiveViewTest
  }

  import Mox

  # alias ArchethicWeb.Explorer.{RewardChainLive}

  alias Archethic.{
    Crypto,
    # TransactionChain,
    TransactionChain.Transaction
  }

  setup do
    reward_chain_genesis_address =
      0
      |> Crypto.reward_public_key()
      |> Crypto.derive_address()

    :persistent_term.put(:reward_gen_addr, reward_chain_genesis_address)

    MockDB
    |> stub(:list_chain_addresses, fn ^reward_chain_genesis_address ->
      Stream.map(1..35, fn index ->
        address =
          index
          |> Crypto.reward_public_key()
          |> Crypto.derive_address()

        time =
          DateTime.utc_now()
          |> DateTime.add(3600 * index, :second)

        {address, time}
      end)
    end)
    |> stub(:get_transaction, fn _address, [:type], _ ->
      {:ok,
       %Transaction{
         type: :node_rewards
       }}
    end)
    |> stub(:count_transactions_by_type, fn
      :node_rewards ->
        35

      :mint_rewards ->
        0
    end)

    on_exit(fn -> :persistent_term.put(:reward_gen_addr, nil) end)

    :ok
  end

  describe "mount/3" do
    test "should render", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/explorer/chain/rewards")

      assert html =~ "Reward chain"
    end
  end

  describe "handle_event/3 event, params, socket" do
    test "Should go to next Page", %{conn: conn} do
      {:ok, view, html} = live(conn, "/explorer/chain/rewards")
      assert html =~ "Reward chain"

      render_click(view, "goto", %{"page" => 2})
      assert_patch(view, "/explorer/chain/rewards?page=2")
    end
  end
end
