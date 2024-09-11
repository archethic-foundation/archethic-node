defmodule Archethic.Utils.Regression.Playbook.SmartContract.Dex do
  @moduledoc """
  This contract is triggered by transactions
  It starts with content=0 and the number will increment for each transaction received
  """

  alias Archethic.Crypto
  alias Archethic.Mining.LedgerValidation
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.Utils.Regression.Api
  alias Archethic.Utils.Regression.Playbook.SmartContract

  require Logger

  @unit_uco 100_000_000

  def play(storage_nonce_pubkey, endpoint) do
    Logger.info("============== CONTRACT: DEX ==============")

    [
      concurrent_add_liquidity(storage_nonce_pubkey, endpoint),
      concurrent_add_and_remove_liquidity(storage_nonce_pubkey, endpoint)
    ]
    |> Enum.find(:ok, &(&1 == :error))
  end

  defp concurrent_add_liquidity(storage_nonce_pubkey, endpoint) do
    nb_triggers = 50

    Logger.info("Concurrent add liquidity with #{nb_triggers} triggers")

    seeds = init_seeds(nb_triggers)
    fund_seeds(seeds, endpoint)
    create_tokens(seeds, endpoint)
    deploy_contract(seeds, storage_nonce_pubkey, endpoint)

    opts_list = Enum.map(1..nb_triggers, fn _ -> add_liquidity_opts(seeds, 10, 10) end)

    triggers(seeds, opts_list, endpoint)

    await_no_more_calls(seeds, endpoint)

    state = get_contrat_state(seeds, endpoint)

    expected_lp_token_supply = nb_triggers * 10
    expected_reserves = %{"token1" => nb_triggers * 10, "token2" => nb_triggers * 10}

    case state do
      %{"lp_token_supply" => lp_token_supply, "reserves" => reserves}
      when reserves == expected_reserves and lp_token_supply == expected_lp_token_supply ->
        Logger.info("Contract state has expected values")

      state ->
        Logger.error("Contract state is invalid")
        Logger.debug(state)
    end

    %{lp_token_address: lp_token_address, triggers_addresses: triggers_addresses} = seeds
    lp_token_address = Base.encode16(lp_token_address)

    frequencies =
      Task.async_stream(triggers_addresses, fn address ->
        address
        |> Api.get_unspent_outputs(endpoint)
        |> Enum.find(%{"amount" => 0}, &(Map.get(&1, "tokenAddress") == lp_token_address))
        |> Map.get("amount")
      end)
      |> Enum.map(fn {:ok, res} -> res end)
      |> Enum.frequencies()

    case frequencies do
      %{999_999_990 => 1, 1_000_000_000 => nb} when nb == nb_triggers - 1 ->
        Logger.info("Triggers received expected LP Tokens")
        :ok

      frequencies ->
        Logger.error("Triggers received invalid LP Tokens")
        Logger.debug(frequencies)
        :error
    end
  end

  defp concurrent_add_and_remove_liquidity(storage_nonce_pubkey, endpoint) do
    nb_triggers = 50

    Logger.info("Concurrent add / remove liquidity with #{nb_triggers} triggers")

    seeds = init_seeds(nb_triggers)
    fund_seeds(seeds, endpoint)
    create_tokens(seeds, endpoint)
    deploy_contract(seeds, storage_nonce_pubkey, endpoint)

    nb_remove_liquidity = trunc(nb_triggers / 2)
    nb_add_liquidity = nb_triggers - nb_remove_liquidity

    add_liquidity_opts_list =
      Enum.map(1..nb_add_liquidity, fn _ -> add_liquidity_opts(seeds, 10, 10) end)

    seeds
    |> Map.update!(:triggers_seeds, &Enum.take(&1, nb_remove_liquidity))
    |> triggers(add_liquidity_opts_list, endpoint)

    await_no_more_calls(seeds, endpoint)

    remove_liquidity_opts_list =
      Enum.map(1..nb_remove_liquidity, fn _ -> remove_liquidity_opts(seeds, 5) end)

    add_liquidity_opts_list =
      Enum.map((nb_remove_liquidity + 1)..nb_triggers, fn _ ->
        add_liquidity_opts(seeds, 10, 10)
      end)

    opts = remove_liquidity_opts_list ++ add_liquidity_opts_list

    triggers(seeds, opts, endpoint)

    await_no_more_calls(seeds, endpoint)

    state = get_contrat_state(seeds, endpoint)

    expected_lp_token_supply = nb_add_liquidity * 10 + nb_remove_liquidity * 5

    expected_reserves = %{
      "token1" => nb_add_liquidity * 10 + nb_remove_liquidity * 5,
      "token2" => nb_add_liquidity * 10 + nb_remove_liquidity * 5
    }

    case state do
      %{"lp_token_supply" => lp_token_supply, "reserves" => reserves}
      when reserves == expected_reserves and lp_token_supply == expected_lp_token_supply ->
        Logger.info("Contract state has expected values")

      state ->
        Logger.error("Contract state is invalid")
        Logger.debug(state)
    end

    %{lp_token_address: lp_token_address, triggers_addresses: triggers_addresses} = seeds
    lp_token_address = Base.encode16(lp_token_address)

    frequencies =
      Task.async_stream(triggers_addresses, fn address ->
        address
        |> Api.get_unspent_outputs(endpoint)
        |> Enum.find(%{"amount" => 0}, &(Map.get(&1, "tokenAddress") == lp_token_address))
        |> Map.get("amount")
      end)
      |> Enum.map(fn {:ok, res} -> res end)
      |> Enum.frequencies()

    case frequencies do
      %{499_999_990 => 1, 500_000_000 => nb5, 1_000_000_000 => nb10}
      when nb5 == nb_remove_liquidity - 1 and nb10 == nb_add_liquidity ->
        Logger.info("Triggers received expected LP Tokens")
        :ok

      frequencies ->
        Logger.error("Triggers received invalid LP Tokens")
        Logger.debug(frequencies)
        :error
    end
  end

  defp init_seeds(nb_triggers) do
    pool_seed = SmartContract.random_seed()
    token1_seed = SmartContract.random_seed()
    token2_seed = SmartContract.random_seed()
    protocol_fee_seed = SmartContract.random_seed()
    triggers_seeds = Enum.map(1..nb_triggers, fn _ -> SmartContract.random_seed() end)

    %{
      pool_seed: pool_seed,
      token1_seed: token1_seed,
      token2_seed: token2_seed,
      protocol_fee_seed: protocol_fee_seed,
      triggers_seeds: triggers_seeds,
      pool_address: derive_address(pool_seed, 0),
      lp_token_address: derive_address(pool_seed, 1),
      token1_address: derive_address(token1_seed, 1),
      token2_address: derive_address(token2_seed, 1),
      protocol_fee_address: derive_address(protocol_fee_seed, 0),
      triggers_addresses: Enum.map(triggers_seeds, &derive_address(&1, 0))
    }
  end

  defp fund_seeds(
         %{
           pool_seed: pool_seed,
           token1_seed: token1_seed,
           token2_seed: token2_seed,
           triggers_seeds: triggers_seeds
         },
         endpoint
       ) do
    triggers_seeds
    |> Enum.reduce(
      %{pool_seed => 10, token1_seed => 100, token2_seed => 100},
      fn seed, acc -> Map.put(acc, seed, 10) end
    )
    |> Api.send_funds_to_seeds(endpoint)
  end

  defp deploy_contract(
         %{
           pool_seed: pool_seed,
           pool_address: genesis_address,
           protocol_fee_address: protocol_fee_address,
           token1_address: token1_address,
           token2_address: token2_address,
           lp_token_address: lp_token_address
         },
         storage_nonce_pubkey,
         endpoint
       ) do
    genesis_address = Base.encode16(genesis_address)
    lp_token_address = Base.encode16(lp_token_address)
    token1_address = Base.encode16(token1_address)
    token2_address = Base.encode16(token2_address)
    protocol_fee_address = Base.encode16(protocol_fee_address)

    SmartContract.deploy(
      pool_seed,
      %TransactionData{
        code:
          pool_code(
            token1_address,
            token2_address,
            genesis_address,
            lp_token_address,
            protocol_fee_address
          ),
        content: pool_content(token1_address, token2_address)
      },
      storage_nonce_pubkey,
      endpoint
    )
  end

  defp derive_address(seed, index),
    do: Crypto.derive_keypair(seed, index) |> elem(0) |> Crypto.derive_address()

  defp await_no_more_calls(%{pool_address: contract_address}, endpoint) do
    SmartContract.await_no_more_calls(contract_address, endpoint)
  end

  defp get_contrat_state(%{pool_address: contract_address}, endpoint) do
    contract_address
    |> Api.get_unspent_outputs(endpoint)
    |> Enum.find(&(Map.get(&1, "type") == "state"))
    |> Map.get("state")
  end

  defp create_tokens(
         %{
           token1_seed: token1_seed,
           token2_seed: token2_seed,
           triggers_addresses: triggers_addresses
         },
         endpoint
       ) do
    recipients =
      Enum.map(triggers_addresses, fn address ->
        %{to: Base.encode16(address), amount: 10 * @unit_uco}
      end)

    token_spec = %{
      supply: Enum.map(recipients, & &1.amount) |> Enum.sum(),
      type: "fungible",
      name: "token1",
      symbol: "token1",
      recipients: recipients
    }

    data = %TransactionData{content: Jason.encode!(token_spec)}
    Api.send_transaction_with_await_replication(token1_seed, :token, data, endpoint)

    token_spec = token_spec |> Map.put(:name, "token2") |> Map.put(:symbol, "token2")
    data = %TransactionData{content: Jason.encode!(token_spec)}
    Api.send_transaction_with_await_replication(token2_seed, :token, data, endpoint)
  end

  defp add_liquidity_opts(
         %{
           pool_address: genesis_address,
           token1_address: token1_address,
           token2_address: token2_address
         },
         token1_amount,
         token2_amount
       ) do
    recipients = [
      %Recipient{
        address: genesis_address,
        action: "add_liquidity",
        args: [token1_amount, token2_amount]
      }
    ]

    ledger = %Ledger{
      token: %TokenLedger{
        transfers: [
          %TokenTransfer{
            to: genesis_address,
            amount: token1_amount * @unit_uco,
            token_address: token1_address,
            token_id: 0
          },
          %TokenTransfer{
            to: genesis_address,
            amount: token2_amount * @unit_uco,
            token_address: token2_address,
            token_id: 0
          }
        ]
      }
    }

    [ledger: ledger, recipients: recipients]
  end

  defp remove_liquidity_opts(
         %{pool_address: genesis_address, lp_token_address: lp_token_address},
         lp_token_amount
       ) do
    recipients = [%Recipient{address: genesis_address, action: "remove_liquidity", args: []}]

    ledger = %Ledger{
      token: %TokenLedger{
        transfers: [
          %TokenTransfer{
            to: LedgerValidation.burning_address(),
            amount: lp_token_amount * @unit_uco,
            token_address: lp_token_address,
            token_id: 0
          }
        ]
      }
    }

    [ledger: ledger, recipients: recipients]
  end

  defp triggers(
         %{triggers_seeds: triggers_seeds, pool_address: genesis_address},
         opts_list,
         endpoint
       ) do
    triggers_seeds
    |> Enum.zip(opts_list)
    |> Enum.shuffle()
    |> Task.async_stream(
      fn {seed, opts} -> trigger(seed, genesis_address, opts, endpoint) end,
      max_concurrency: length(triggers_seeds),
      timeout: :infinity
    )
    |> Stream.run()
  end

  defp trigger(seed, contract_address, opts, endpoint) do
    opts = opts |> Keyword.merge(await_timeout: 60_000)
    SmartContract.trigger(seed, contract_address, endpoint, opts)
  end

  defp pool_code(
         token1_address,
         token2_address,
         genesis_address,
         lp_token_address,
         protocol_fee_address
       ) do
    ~s"""
    @version 1

    condition triggered_by: transaction, on: add_liquidity(token1_min_amount, token2_min_amount), as: [
      token_transfers: (
        user_amounts = get_user_transfers_amount(transaction)

        valid_transfers? = user_amounts.token1 > 0 && user_amounts.token2 > 0
        valid_min? = user_amounts.token1 >= token1_min_amount && user_amounts.token2 >= token2_min_amount

        valid_transfers? && valid_min?
      )
    ]

    actions triggered_by: transaction, on: add_liquidity(token1_min_amount, token2_min_amount) do
      pool_balances = get_pool_balances()
      user_amounts = get_user_transfers_amount(transaction)

      lp_token_supply = State.get("lp_token_supply", 0)
      reserves = State.get("reserves", [token1: 0, token2: 0])

      final_amounts = get_final_amounts(user_amounts, reserves, token1_min_amount, token2_min_amount)
      token1_to_refund = user_amounts.token1 - final_amounts.token1
      token2_to_refund = user_amounts.token2 - final_amounts.token2

      token1_amount = user_amounts.token1 + pool_balances.token1 - reserves.token1 - token1_to_refund
      token2_amount = user_amounts.token2 + pool_balances.token2 - reserves.token2 - token2_to_refund

      lp_token_to_mint = get_lp_token_to_mint(token1_amount, token2_amount)

      # Handle invalid values and refund user 
      valid_amounts? = final_amounts.token1 > 0 && final_amounts.token2 > 0
      valid_liquidity? = lp_token_to_mint > 0

      if valid_amounts? && valid_liquidity? do
        lp_token_to_mint_bigint = Math.trunc(lp_token_to_mint * 100_000_000)

        # Remove minimum liquidity if this is the first liquidity if the pool
        # First liquidity minted and burned on pool creation
        if lp_token_supply == 0 do
          lp_token_to_mint_bigint = lp_token_to_mint_bigint - 10
        end

        token_specification = [
          aeip: [8, 18, 19],
          supply: lp_token_to_mint_bigint,
          token_reference: @LP_TOKEN,
          recipients: [
            [to: transaction.address, amount: lp_token_to_mint_bigint]
          ]
        ]

        new_token1_reserve = user_amounts.token1 + pool_balances.token1 - token1_to_refund
        new_token2_reserve = user_amounts.token2 + pool_balances.token2 - token2_to_refund

        State.set("lp_token_supply", lp_token_supply + lp_token_to_mint)
        State.set("reserves", [token1: new_token1_reserve, token2: new_token2_reserve])

        if token1_to_refund > 0 do
          Contract.add_token_transfer(to: transaction.address, amount: token1_to_refund, token_address: @TOKEN1)
        end

        if token2_to_refund > 0 do
          if @TOKEN2 == "UCO" do
            Contract.add_uco_transfer(to: transaction.address, amount: token2_to_refund)
          else
            Contract.add_token_transfer(to: transaction.address, amount: token2_to_refund, token_address: @TOKEN2)
          end
        end

        Contract.set_type("token")
        Contract.set_content(Json.to_string(token_specification))
      else
        # Liquidity provision is invalid, refund user of it's tokens
        Contract.set_type("transfer")

        if @TOKEN2 == "UCO" do
          Contract.add_uco_transfer(to: transaction.address, amount: user_amounts.token2)
        else
          Contract.add_token_transfer(to: transaction.address, amount: user_amounts.token2, token_address: @TOKEN2)
        end

        Contract.add_token_transfer(to: transaction.address, amount: user_amounts.token1, token_address: @TOKEN1)
      end
    end

    condition triggered_by: transaction, on: remove_liquidity(), as: [
      token_transfers: (
        user_amount = get_user_lp_amount(transaction.token_transfers)

        user_amount > 0
      )
    ]

    actions triggered_by: transaction, on: remove_liquidity() do
      return? = true

      user_amount = get_user_lp_amount(transaction.token_transfers)
      lp_token_supply = State.get("lp_token_supply", 0)

      if lp_token_supply > 0 do
        pool_balances = get_pool_balances()

        token1_to_remove = (user_amount * pool_balances.token1) / lp_token_supply
        token2_to_remove = (user_amount * pool_balances.token2) / lp_token_supply

        if token1_to_remove > 0 && token2_to_remove > 0 do
          return? = false

          new_token1_reserve = pool_balances.token1 - token1_to_remove
          new_token2_reserve = pool_balances.token2 - token2_to_remove

          State.set("lp_token_supply", lp_token_supply - user_amount)
          State.set("reserves", [token1: new_token1_reserve, token2: new_token2_reserve])

          Contract.set_type("transfer")
          Contract.add_token_transfer(to: transaction.address, amount: token1_to_remove, token_address: @TOKEN1)
          if @TOKEN2 == "UCO" do
            Contract.add_uco_transfer(to: transaction.address, amount: token2_to_remove)
          else
            Contract.add_token_transfer(to: transaction.address, amount: token2_to_remove, token_address: @TOKEN2)
          end
        end
      end

      if return? do
        # Refund is invalid, return LP tokens to user
        Contract.set_type("transfer")
        Contract.add_token_transfer(to: transaction.address, amount: user_amount, token_address: @LP_TOKEN)
      end
    end

    condition triggered_by: transaction, on: swap(_min_to_receive), as: [
      token_transfers: (
        transfer = get_user_transfer(transaction)

        transfer != nil
      )
    ]

    actions triggered_by: transaction, on: swap(min_to_receive) do
      transfer = get_user_transfer(transaction)

      swap = get_swap_infos(transfer.token_address, transfer.amount)

      if swap.output_amount > 0 && swap.output_amount >= min_to_receive do

        pool_balances = get_pool_balances()
        token_to_send = nil
        token1_volume = 0
        token2_volume = 0
        token1_fee = 0
        token2_fee = 0
        token1_protocol_fee = 0
        token2_protocol_fee = 0
        if transfer.token_address == @TOKEN1 do
          pool_balances = [
            token1: pool_balances.token1 + transfer.amount - swap.protocol_fee,
            token2: pool_balances.token2 - swap.output_amount
          ]
          token_to_send = @TOKEN2
          token1_volume = transfer.amount
          token1_fee = swap.fee
          token1_protocol_fee = swap.protocol_fee
        else
          pool_balances = [
            token1: pool_balances.token1 - swap.output_amount,
            token2: pool_balances.token2 + transfer.amount - swap.protocol_fee
          ]
          token_to_send = @TOKEN1
          token2_volume = transfer.amount
          token2_fee = swap.fee
          token2_protocol_fee = swap.protocol_fee
        end

        State.set("reserves", [token1: pool_balances.token1, token2: pool_balances.token2])

        stats = State.get("stats", [
          token1_total_fee: 0,
          token2_total_fee: 0,
          token1_total_volume: 0,
          token2_total_volume: 0,
          token1_total_protocol_fee: 0,
          token2_total_protocol_fee: 0,
        ])

        token1_total_fee = Map.get(stats, "token1_total_fee") + token1_fee
        token2_total_fee = Map.get(stats, "token2_total_fee") + token2_fee
        token1_total_volume = Map.get(stats, "token1_total_volume") + token1_volume
        token2_total_volume = Map.get(stats, "token2_total_volume") + token2_volume
        token1_total_protocol_fee = Map.get(stats, "token1_total_protocol_fee") + token1_protocol_fee
        token2_total_protocol_fee = Map.get(stats, "token2_total_protocol_fee") + token2_protocol_fee

        stats = Map.set(stats, "token1_total_fee", token1_total_fee)
        stats = Map.set(stats, "token2_total_fee", token2_total_fee)
        stats = Map.set(stats, "token1_total_volume", token1_total_volume)
        stats = Map.set(stats, "token2_total_volume", token2_total_volume)
        stats = Map.set(stats, "token1_total_protocol_fee", token1_total_protocol_fee)
        stats = Map.set(stats, "token2_total_protocol_fee", token2_total_protocol_fee)

        State.set("stats", stats)

        Contract.set_type("transfer")
        if token_to_send == "UCO" do
          Contract.add_uco_transfer(to: transaction.address, amount: swap.output_amount)
        else
          Contract.add_token_transfer(to: transaction.address, amount: swap.output_amount, token_address: token_to_send)
        end

        if swap.protocol_fee > 0 do
          if transfer.token_address == "UCO" do
            Contract.add_uco_transfer(to: @PROTOCOL_FEE_ADDRESS, amount: swap.protocol_fee)
          else
            Contract.add_token_transfer(to: @PROTOCOL_FEE_ADDRESS, amount: swap.protocol_fee, token_address: transfer.token_address)
          end
        end
      else
        # Swap is invalid, return tokens to user
        Contract.set_type("transfer")

        if transfer.token_address == @TOKEN1 do
          Contract.add_token_transfer(to: transaction.address, amount: transfer.amount, token_address: @TOKEN1)
        else
          if transfer.token_address == "UCO" do
            Contract.add_uco_transfer(to: transaction.address, amount: transfer.amount)
          else
            Contract.add_token_transfer(to: transaction.address, amount: transfer.amount, token_address: @TOKEN2)
          end
        end
      end
    end

    export fun get_lp_token_to_mint(token1_amount, token2_amount) do
      lp_token_supply = State.get("lp_token_supply", 0)
      reserves = State.get("reserves", [token1: 0, token2: 0])

      if lp_token_supply == 0 || reserves.token1 == 0 || reserves.token2 == 0 do
        # First liquidity
        Math.sqrt(token1_amount * token2_amount)
      else
        mint_amount1 = (token1_amount * lp_token_supply) / reserves.token1
        mint_amount2 = (token2_amount * lp_token_supply) / reserves.token2

        if mint_amount1 < mint_amount2 do
          mint_amount1
        else
          mint_amount2
        end
      end
    end

    export fun get_swap_infos(token_address, amount) do
      output_amount = 0
      fee = 0
      protocol_fee = 0
      price_impact = 0

      reserves = State.get("reserves", [token1: 0, token2: 0])
      token_address = String.to_uppercase(token_address)

      if reserves.token1 > 0 && reserves.token2 > 0 do
        fee = amount * 0.0025
        protocol_fee = amount * State.get("protocol_fee", 0.25) / 100
        amount_with_fee = amount - fee - protocol_fee

        market_price = 0

        if token_address == @TOKEN1 do
          market_price = amount_with_fee * (reserves.token2 / reserves.token1)
          amount = (amount_with_fee * reserves.token2) / (amount_with_fee + reserves.token1)
          if amount < reserves.token2 do
            output_amount = amount
          end
        else
          market_price = amount_with_fee * (reserves.token1 / reserves.token2)
          amount = (amount_with_fee * reserves.token1) / (amount_with_fee + reserves.token2)
          if amount < reserves.token1 do
            output_amount = amount
          end
        end

        if output_amount > 0 do
          # This check is necessary as there might be some approximation in small decimal calculation
          if market_price > output_amount do
            price_impact = ((market_price / output_amount) - 1) * 100
          else
            price_impact = 0
          end
        end
      end

      [
        output_amount: output_amount,
        fee: fee,
        protocol_fee: protocol_fee,
        price_impact: price_impact
      ]
    end

    fun get_final_amounts(user_amounts, reserves, token1_min_amount, token2_min_amount) do
      final_token1_amount = 0
      final_token2_amount = 0

      if reserves.token1 > 0 && reserves.token2 > 0 do
        token2_ratio = reserves.token2 / reserves.token1
        token2_equivalent_amount = user_amounts.token1 * token2_ratio

        if token2_equivalent_amount <= user_amounts.token2 && token2_equivalent_amount >= token2_min_amount do
          final_token1_amount = user_amounts.token1
          final_token2_amount = token2_equivalent_amount
        else
          token1_ratio = reserves.token1 / reserves.token2
          token1_equivalent_amount = user_amounts.token2 * token1_ratio

          if token1_equivalent_amount <= user_amounts.token1 && token1_equivalent_amount >= token1_min_amount do
            final_token1_amount = token1_equivalent_amount
            final_token2_amount = user_amounts.token2
          end
        end
      else
        # No reserve
        final_token1_amount = user_amounts.token1
        final_token2_amount = user_amounts.token2
      end

      [token1: final_token1_amount, token2: final_token2_amount]
    end

    fun get_user_transfers_amount(tx) do
      contract_address = @POOL_ADDRESS

      token1_amount = 0
      token2_amount = 0
      transfers = Map.get(tx.token_transfers, contract_address, [])

      uco_amount = Map.get(tx.uco_transfers, contract_address)
      if uco_amount != nil do
        transfers = List.prepend(transfers, [token_address: "UCO", amount: uco_amount])
      end

      if List.size(transfers) == 2 do
        for transfer in transfers do
          if transfer.token_address == @TOKEN1 do
            token1_amount = transfer.amount
          end
          if transfer.token_address == @TOKEN2 do
            token2_amount = transfer.amount
          end
        end
      end

      [token1: token1_amount, token2: token2_amount]
    end

    fun get_user_transfer(tx) do
      contract_address = @POOL_ADDRESS

      token_transfer = nil
      transfers = Map.get(tx.token_transfers, contract_address, [])

      uco_amount = Map.get(tx.uco_transfers, contract_address)
      if uco_amount != nil do
        transfers = List.prepend(transfers, [token_address: "UCO", amount: uco_amount])
      end

      transfer = List.at(transfers, 0)

      tokens = [
        @TOKEN1,
        @TOKEN2
      ]

      if List.size(transfers) == 1 && List.in?(tokens, transfer.token_address) do
        token_transfer = transfer
      end

      token_transfer
    end

    fun get_user_lp_amount(token_transfers) do
      lp_token = @LP_TOKEN

      lp_amount = 0
      transfers = Map.get(token_transfers, Chain.get_burn_address(), [])

      for transfer in transfers do
        if transfer.token_address == lp_token do
          lp_amount = transfer.amount
        end
      end

      lp_amount
    end

    fun get_pool_balances() do
      token2_balance = 0
      if @TOKEN2 == "UCO" do
        token2_balance = contract.balance.uco
      else
        token2_id = [token_address: @TOKEN2, token_id: 0]
        token2_balance = Map.get(contract.balance.tokens, token2_id, 0)
      end

      token1_id = [token_address: @TOKEN1, token_id: 0]
      [
        token1: Map.get(contract.balance.tokens, token1_id, 0),
        token2: token2_balance
      ]
    end
    """
    |> String.replace("@TOKEN1", "0x" <> token1_address)
    |> String.replace("@TOKEN2", "0x" <> token2_address)
    |> String.replace("@POOL_ADDRESS", "0x" <> genesis_address)
    |> String.replace("@LP_TOKEN", "0x" <> lp_token_address)
    |> String.replace("@PROTOCOL_FEE_ADDRESS", "0x" <> protocol_fee_address)
  end

  defp pool_content(token1_address, token2_address) do
    %{
      aeip: [2, 8, 18, 19],
      supply: 10,
      type: "fungible",
      symbol: "aeSwapLP",
      name: "aeSwap LP Token",
      allow_mint: true,
      properties: %{token1_address: token1_address, token2_address: token2_address},
      recipients: [%{to: LedgerValidation.burning_address(), amount: 10}]
    }
    |> Jason.encode!()
  end
end
