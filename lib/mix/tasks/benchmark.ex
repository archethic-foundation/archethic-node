defmodule Mix.Tasks.Archethic.Benchmark do
  @moduledoc "Drop all the data from the database"

  use Mix.Task

  alias Archethic.Crypto

  @impl Mix.Task
  def run(_arg) do
    {ed_keypairs, bls_keypairs} =
      Enum.map(1..200, fn _ ->
        seed = :crypto.strong_rand_bytes(32)
        bls_keypair = Crypto.generate_deterministic_keypair(seed, :bls)
        ed_keypair = Crypto.generate_deterministic_keypair(seed)

        {ed_keypair, bls_keypair}
      end)
      |> Enum.unzip()

    data = "hello"

    ed_sig_by_pub = Enum.map(ed_keypairs, fn {pub, priv} -> {pub, Crypto.sign(data, priv)} end)

    {bls_pubs, bls_sigs} =
      Enum.map(bls_keypairs, fn {pub, priv} -> {pub, Crypto.sign(data, priv)} end) |> Enum.unzip()

    bls_agg_sig = Crypto.aggregate_signatures(bls_sigs, bls_pubs)

    Benchee.run(%{
      "Verifying 200 ed25519 signatures" => fn ->
        Task.async_stream(ed_sig_by_pub, fn {pub, sig} -> Crypto.verify?(sig, data, pub) end,
          max_concurrency: 200
        )
        |> Enum.all?()
      end,
      "Verifying aggregation of 200 bls signatures" => fn ->
        agg_pub = Crypto.aggregate_mining_public_keys(bls_pubs)
        Crypto.verify?(bls_agg_sig, data, agg_pub)
      end
    })
  end
end
