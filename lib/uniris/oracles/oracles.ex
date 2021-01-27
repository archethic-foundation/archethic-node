defmodule Uniris.Oracles do
  @moduledoc false

  # Defined in transaction.ex:
    # TX type :oracle
    # :oracle is a network tx with fee 0
    # :oracle serialized to 11

  alias __MODULE__.Coingecko

  def fetch_uco_price do
    res1 = Coingecko.start()

    price = Coingecko.get!("23-01-2021")
    |> Map.fetch!(:body)
    |> Map.fetch!("market_data")
    |> Map.fetch!("current_price")
    |> Map.fetch!("eur")

    content = %{"eur" => price}
    |> Jason.encode!
    |> Base.encode16
    IO.puts "RES1: #{inspect content}"

    # IO.puts "RES2: #{inspect content}"

    # secret = Base.decode16!(secret, case: :mixed)

    # authorized_keys = Enum.reduce(authorized_keys, %{}, fn {public_key, encrypted_secret_key}, acc ->
    #   Map.put(
    #     acc,
    #     Base.decode16!(public_key, case: :mixed),
    #     Base.decode16!(encrypted_secret_key, case: :mixed)
    #   )
    # end)

    # keys = %Keys{
    #   secret: secret,
    #   authorized_keys: authorized_keys
    # }

    # nft = %NFTLedger{
    #   transfers:
    #     Enum.map(nft_transfers, fn %{"nft" => nft, "to" => to, "amount" => amount} ->
    #       %NFTTransfer{
    #         nft: Base.decode16!(nft, case: :mixed),
    #         to: Base.decode16!(to, case: :mixed),
    #         amount: amount
    #       }
    #     end)
    # }

    # ledger = %Ledger{nft: nft}

    # recipients = &Base.decode16!("6CBF75F092278AA0751096CE85FE1E1F033FF50312B146DB336FAF861C8C4E09", case: :mixed)

    data = %Uniris.TransactionChain.TransactionData{content: content}

    tx = Uniris.TransactionChain.Transaction.new(:oracle, data)
    :ok = Uniris.send_new_transaction(tx)
  end
end

# 1. What should be added to %TransactionData{}
# 2. Validation nodes: P2P.list_nodes(authorized?: true, availability: :local) -> :local | :global
# 3. [
  # %Uniris.P2P.Node{
  #   authorization_date: ~U[2021-01-24 12:11:40.966Z], 
  #   authorized?: true, 
  #   availability_history: <<1::size(1)>>, 
  #   available?: false, <-------------------------------------- false?
  #   average_availability: 1.0, 
  #   enrollment_date: ~U[2021-01-24 12:08:20.169Z], 
  #   first_public_key: <<0, 104, 47, 243, 2, 191, 168, 71, 2, 160, 13, 129, 213, 249, 118, 16, 224, 37, 115, 192, 72, 127, 188, 214, 208, 10, 102, 204, 188, 14, 6, 86, 232>>, geo_patch: "34A", ip: {127, 0, 0, 1}, last_public_key: <<0, 104, 47, 243, 2, 191, 168, 71, 2, 160, 13, 129, 213, 249, 118, 16, 224, 37, 115, 192, 72, 127, 188, 214, 208, 10, 102, 204, 188, 14, 6, 86, 232>>, 
  #   network_patch: "34A", 
  #   port: 3002, 
  #   transport: :tcp
  # }]