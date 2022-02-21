defmodule ArchEthic.ReleaseTask do
  @moduledoc """
  Task using in the release to send initial funds to the addresses of the onchain
  version of the website
  """

  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer

  # TODO: to remove once the Client UI developed
  def transfer_to_website_addresses(amount \\ 1.0) do
    seed = Base.decode16!("6CBF75F092278AA0751096CE85FE1E1F033FF50312B146DB336FAF861C8C4E09")

    Transaction.new(
      :transfer,
      %TransactionData{
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers:
              Enum.map(website_seeds(), fn destination_seed ->
                {pub, _} =
                  Crypto.derive_keypair(destination_seed, get_last_index(destination_seed))

                %Transfer{to: Crypto.derive_address(pub), amount: amount}
              end)
          }
        }
      },
      seed,
      get_last_index(seed)
    )
    |> ArchEthic.send_new_transaction()
  end

  defp get_last_index(seed) do
    address =
      seed
      |> Crypto.derive_keypair(0)
      |> elem(0)
      |> Crypto.derive_address()

    case ArchEthic.get_last_transaction(address) do
      {:ok, %Transaction{address: address}} ->
        ArchEthic.get_transaction_chain_length(address)

      _ ->
        0
    end
  end

  defp website_seeds do
    [
      Crypto.derive_address("animate_seed"),
      Crypto.derive_address("bicon_seed"),
      Crypto.derive_address("bootstrap_css_seed"),
      Crypto.derive_address("bootstrap_js_seed"),
      Crypto.derive_address("fontawesome_seed"),
      Crypto.derive_address("carousel_seed"),
      Crypto.derive_address("jquery_seed"),
      Crypto.derive_address("magnificpopup_css_seed"),
      Crypto.derive_address("archethic_css_seed"),
      Crypto.derive_address("owlcarousel_css_seed"),
      Crypto.derive_address("owlcarousel_js_seed"),
      Crypto.derive_address("popper_seed"),
      Crypto.derive_address("wow_seed"),
      Crypto.derive_address("jquerycountdown_seed"),
      Crypto.derive_address("magnificpopup_js_seed"),
      Crypto.derive_address("particles_seed"),
      Crypto.derive_address("archethic_js_seed"),
      Crypto.derive_address("d3_seed"),
      Crypto.derive_address("d3queue_seed"),
      Crypto.derive_address("d3topojson_seed"),
      Crypto.derive_address("archethic_biometricanim_seed"),
      Crypto.derive_address("archethic_blockchainanim_seed"),
      Crypto.derive_address("formvalidator_seed"),
      Crypto.derive_address("world-110_seed"),
      Crypto.derive_address("archethic_index_seed"),
      Crypto.derive_address("archethic_index_fr_seed"),
      Crypto.derive_address("archethic_index_ru_seed"),
      Crypto.derive_address("archethic_whitepaper_seed"),
      Crypto.derive_address("archethic_whitepaper_fr_seed"),
      Crypto.derive_address("archethic_yellowpaper_s1_seed"),
      Crypto.derive_address("archethic_yellowpaper_s1_fr_seed")
    ]
  end
end
