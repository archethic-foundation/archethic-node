defmodule ArchethicWeb.API.Schema.OriginPublicKeyTest do
  @moduledoc false
  use ArchethicCase

  use Ecto.Schema

  alias ArchethicWeb.API.Schema.OriginPublicKey
  alias Archethic.{P2P, P2P.Node, SharedSecrets, SharedSecrets.MemTables.OriginKeyLookup}

  describe "OriginPublicKey Schema Test" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "irst",
        last_public_key: "last",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      OriginKeyLookup.start_link()

      :ok
    end

    test "Should return Error, when Origin Public Key is empty" do
      params = parameters(_origin_public_key = "", _certificate = "")

      assert [{:origin_public_key, {"can't be blank", [validation: :required]}}] ==
               OriginPublicKey.changeset(params).errors
    end

    test "Should return invalid key size" do
      params = parameters("0001540315", "")

      change_set = OriginPublicKey.changeset(params)
      assert [origin_public_key: {"invalid key size", _}] = change_set.errors
    end

    test "Should return must be hexadecimal" do
      params =
        parameters("00015403152aeb59b1b584d77c8f326031815674afeade8cba25f18f02737d599ZZZ", "")

      change_set = OriginPublicKey.changeset(params)

      assert [origin_public_key: {"must be hexadecimal", _}] = change_set.errors
    end

    test "Should return Already Exists" do
      {public_key_bin, public_key} = gen_public_key()

      OriginKeyLookup.add_public_key(:software, public_key_bin)
      assert true == SharedSecrets.has_origin_public_key?(public_key_bin)

      params = parameters(_origin_public_key = public_key, _certificate = "")

      change_set = OriginPublicKey.changeset(params)

      assert [origin_public_key: {"Already Exists", _}] = change_set.errors
    end

    test "Should Accept, Empty certificate  Valid OriginPublicKey" do
      {public_key_bin, public_key} = gen_public_key()
      refute SharedSecrets.has_origin_public_key?(public_key_bin)

      params = parameters(_origin_public_key = public_key, _certificate = "")
      assert [] == OriginPublicKey.changeset(params).errors
    end

    test "Should Return Error: Must Be Hexadecimal, with Certificate having erroneous hexadecimal value" do
      {public_key_bin, public_key} = gen_public_key()
      refute SharedSecrets.has_origin_public_key?(public_key_bin)

      params = parameters(_origin_public_key = public_key, _certificate = "ZZZ")

      assert [
               {:certificate,
                {"must be hexadecimal", [type: ArchethicWeb.API.Types.Hex, validation: :cast]}}
             ] == OriginPublicKey.changeset(params).errors
    end

    test "Should Return Invalid Certificate, with erroneous Certificate Value" do
      {public_key_bin, public_key} = gen_public_key()
      refute SharedSecrets.has_origin_public_key?(public_key_bin)

      params = parameters(_origin_public_key = public_key, _certificate = gen_certificate())

      assert [certificate: {"Invalid Certificate", []}] = OriginPublicKey.changeset(params).errors
    end

    test "Should Return Error-Certificate: Size Exceeds Limit,when Certificate Size Exceeds Limit" do
      {public_key_bin, public_key} = gen_public_key()
      refute SharedSecrets.has_origin_public_key?(public_key_bin)

      params = parameters(_origin_public_key = public_key, _certificate = gen_certificate(9057))

      assert [
               certificate: {"Certificate size exceeds limit", _}
             ] = OriginPublicKey.changeset(params).errors
    end

    test "Should Accept empty Certificate" do
      {public_key_bin, public_key} = gen_public_key()
      refute SharedSecrets.has_origin_public_key?(public_key_bin)

      params = parameters(_origin_public_key = public_key, _certificate = "")

      assert [] = OriginPublicKey.changeset(params).errors
    end
  end

  def parameters(origin_public_key, certifcate) do
    %{
      origin_public_key: origin_public_key,
      certificate: certifcate
    }
  end

  def gen_public_key(origin_limit \\ [0, 1, 2]) do
    #  :0,on_chain_wallet, 1 :software,2  :tpm
    public_key_bin = <<0::8, Enum.random(origin_limit)::8, :crypto.strong_rand_bytes(32)::binary>>

    {public_key_bin, Base.encode16(public_key_bin)}
  end

  def gen_certificate(size \\ :binary.decode_unsigned(:crypto.strong_rand_bytes(1))) do
    Base.encode16(<<0::8, 0::8, :crypto.strong_rand_bytes(size)::binary>>)
  end
end
