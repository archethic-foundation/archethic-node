defmodule UnirisCore.ReleaseTasks.Transfer do
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.TransactionData.Ledger.Transfer
  alias UnirisCore.Crypto

  def to_website_addresses(index \\ 0, destination_index \\ 0, amount \\ 1.0) do
    Transaction.new(
      :transfer,
      %TransactionData{
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers:
              Enum.map(website_seeds(), fn seed ->
                {pub, _} = Crypto.derivate_keypair(seed, destination_index)
                %Transfer{to: Crypto.hash(pub), amount: amount}
              end)
          }
        }
      },
      "6CBF75F092278AA0751096CE85FE1E1F033FF50312B146DB336FAF861C8C4E09",
      index
    )
    |> UnirisCore.send_new_transaction()
  end

  defp website_seeds() do
    [
      "animate_seed",
      "bicon_seed",
      "bootstrap_css_seed",
      "bootstrap_js_seed",
      "fontawesome_seed",
      "carousel_seed",
      "jquery_seed",
      "magnificpopup_css_seed",
      "uniris_css_seed",
      "owlcarousel_css_seed",
      "owlcarousel_js_seed",
      "popper_seed",
      "wow_seed",
      "jquerycountdown_seed",
      "magnificpopup_js_seed",
      "particles_seed",
      "uniris_js_seed",
      "d3_seed",
      "d3queue_seed",
      "d3topojson_seed",
      "uniris_biometricanim_seed",
      "uniris_blockchainanim_seed",
      "formvalidator_seed",
      "world-110_seed",
      "uniris_index_seed",
      "uniris_index_fr_seed",
      "uniris_index_ru_seed",
      "uniris_whitepaper_seed",
      "uniris_whitepaper_fr_seed",
      "uniris_yellowpaper_s1_seed",
      "uniris_yellowpaper_s1_fr_seed"
    ]
  end
end
