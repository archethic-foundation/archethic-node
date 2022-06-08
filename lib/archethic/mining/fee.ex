defmodule Archethic.Mining.Fee do
  @moduledoc """
  Manage the transaction fee calculcation
  """
  alias Archethic.Bootstrap

  alias Archethic.Election

  alias Archethic.P2P

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.NFTLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  @min_tx_fee_in_usd 0.1
  @unit_uco 100_000_000

  @doc """
  Determine the fee to paid for the given transaction

  The fee will differ according to the transaction type and complexity
  Genesis, network and wallet transaction cost nothing.

  """
  @spec calculate(transaction :: Transaction.t(), uco_usd_price :: float()) :: non_neg_integer()
  def calculate(%Transaction{type: :keychain}, _), do: 0
  def calculate(%Transaction{type: :keychain_access}, _), do: 0

  def calculate(
        tx = %Transaction{
          address: address,
          type: type
        },
        uco_price_in_usd
      ) do
    cond do
      address == Bootstrap.genesis_address() ->
        0

      true == Transaction.network_type?(type) ->
        0

      type == :oracle ->
        0.01 / uco_price_in_usd

      true ->
        transaction_value = get_transaction_value(tx) / @unit_uco
        nb_recipients = get_number_recipients(tx)
        nb_bytes = get_transaction_size(tx)
        nb_storage_nodes = get_number_replicas(tx)

        trunc(
          do_calculate(
            uco_price_in_usd,
            transaction_value,
            nb_bytes,
            nb_storage_nodes,
            nb_recipients
          ) * @unit_uco
        )
    end
  end

  defp get_transaction_value(%Transaction{
         data: %TransactionData{ledger: %Ledger{uco: %UCOLedger{transfers: uco_transfers}}}
       }) do
    Enum.reduce(uco_transfers, 0, &(&1.amount + &2))
  end

  defp get_transaction_size(tx = %Transaction{}) do
    tx
    |> Transaction.to_pending()
    |> Transaction.serialize()
    |> byte_size()
  end

  defp get_number_recipients(%Transaction{
         data: %TransactionData{
           ledger: %Ledger{
             uco: %UCOLedger{transfers: uco_transfers},
             nft: %NFTLedger{transfers: nft_transfers}
           }
         }
       }) do
    (uco_transfers ++ nft_transfers)
    |> Enum.uniq_by(& &1.to)
    |> length()
  end

  defp get_number_replicas(%Transaction{address: address}) do
    # TODO: take the nodes at the time of the transaction's timestamp
    address
    |> Election.chain_storage_nodes(P2P.authorized_nodes())
    |> length()
  end

  defp do_calculate(
         uco_price_in_usd,
         transaction_value,
         nb_bytes,
         nb_storage_nodes,
         nb_recipients
       ) do
    # TODO: determine the fee for smart contract execution

    value_cost = fee_for_value(uco_price_in_usd, transaction_value)

    storage_cost =
      fee_for_storage(
        uco_price_in_usd,
        nb_bytes,
        nb_storage_nodes
      )

    replication_cost = cost_per_recipients(nb_recipients, uco_price_in_usd)

    value_cost + storage_cost + replication_cost
  end

  # if transaction value less than minimum transaction value => txn fee is minimum txn fee
  defp fee_for_value(uco_price_in_usd, transaction_value_in_uco)
       when transaction_value_in_uco <= @min_tx_fee_in_usd / uco_price_in_usd * 1000 do
    get_min_transaction_fee(uco_price_in_usd)
  end

  defp fee_for_value(uco_price_in_usd, transaction_value_in_uco) do
    min_tx_fee = get_min_transaction_fee(uco_price_in_usd)
    min_tx_value = min_tx_fee * 1_000
    min_tx_fee * (transaction_value_in_uco / min_tx_value)
  end

  defp get_min_transaction_fee(uco_price_in_usd) do
    @min_tx_fee_in_usd / uco_price_in_usd
  end

  defp fee_for_storage(uco_price_in_usd, nb_bytes, nb_storage_nodes) do
    price_per_byte = 1.0e-8 / uco_price_in_usd
    price_per_storage_node = price_per_byte * nb_bytes
    price_per_storage_node * nb_storage_nodes
  end

  # Send transaction to a single recipient does not include an additional cost
  defp cost_per_recipients(1, _), do: 0

  # Send transaction to multiple recipients (for bulk transfers) will generate an additional cost
  # As more storage pools are required to send the transaction
  defp cost_per_recipients(nb_recipients, uco_price_in_usd) do
    nb_recipients * (0.1 / uco_price_in_usd)
  end
end
