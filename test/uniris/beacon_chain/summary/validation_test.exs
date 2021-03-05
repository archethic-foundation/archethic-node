defmodule Uniris.BeaconChain.SummaryValidationTest do
  use UnirisCase

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.SummaryTimer
  alias Uniris.BeaconChain.SummaryValidation

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Node

  setup do
    start_supervised!({SummaryTimer, interval: "0 0 * * *"})
    start_supervised!({SlotTimer, interval: "0 * * * *"})
    :ok
  end

  import Mox

  describe "storage_node?/1" do
    test "should return true when the node is a storage node for the summary from the slot" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(0),
        available?: true,
        geo_patch: "AAA",
        enrollment_date: DateTime.utc_now()
      })

      assert true ==
               SummaryValidation.storage_node?(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})
    end

    test "should return false when the node is a storage node for the summary from the slot" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        available?: true,
        geo_patch: "AAA",
        enrollment_date: DateTime.utc_now()
      })

      assert false ==
               SummaryValidation.storage_node?(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})
    end
  end

  describe "valid_previous_hash?/1" do
    test "should return true when no previous slot and previous hash is the genesis one" do
      MockDB
      |> expect(:get_beacon_slot, fn _, _ -> {:error, :not_found} end)

      assert true ==
               SummaryValidation.valid_previous_hash?(%Slot{
                 subset: <<1>>,
                 slot_time: DateTime.utc_now()
               })
    end

    test "should return false when no previous slot and previous hash is not the good one" do
      MockDB
      |> expect(:get_beacon_slot, fn _, _ -> {:error, :not_found} end)

      assert false ==
               SummaryValidation.valid_previous_hash?(%Slot{
                 subset: <<1>>,
                 slot_time: DateTime.utc_now(),
                 previous_hash: :crypto.strong_rand_bytes(32)
               })
    end

    test "should return true when a previous slot is stored and previous hash is the good one" do
      date_ref = DateTime.utc_now()

      MockDB
      |> expect(:get_beacon_slot, fn _, _ ->
        {:ok, %Slot{subset: <<0>>, slot_time: DateTime.add(date_ref, -1)}}
      end)

      previous_hash =
        %Slot{subset: <<0>>, slot_time: DateTime.add(date_ref, -1)}
        |> Slot.serialize()
        |> Crypto.hash()

      assert true ==
               SummaryValidation.valid_previous_hash?(%Slot{
                 subset: <<1>>,
                 slot_time: date_ref,
                 previous_hash: previous_hash
               })
    end

    test "should return false when a previous slot is stored and previous hash isn't the good one" do
      date_ref = DateTime.utc_now()

      MockDB
      |> expect(:get_beacon_slot, fn _, _ ->
        {:ok, %Slot{subset: <<0>>, slot_time: DateTime.add(date_ref, -1)}}
      end)

      assert false ==
               SummaryValidation.valid_previous_hash?(%Slot{
                 subset: <<1>>,
                 slot_time: date_ref,
                 previous_hash: :crypto.strong_rand_bytes(32)
               })
    end
  end

  describe "valid_signature?/1" do
    test "should return when the signatures are valid" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(0),
        available?: true,
        geo_patch: "AAA",
        enrollment_date: ~U[2021-01-20 15:17:00Z]
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3050,
        first_public_key: Crypto.node_public_key(1),
        last_public_key: Crypto.node_public_key(1),
        available?: true,
        geo_patch: "AAA",
        enrollment_date: ~U[2021-01-20 15:17:00Z]
      })

      slot = %Slot{subset: <<0>>, slot_time: ~U[2021-01-22 15:17:00Z]}

      sig1 =
        slot
        |> Slot.digest()
        |> Crypto.sign_with_node_key(0)

      sig2 =
        slot
        |> Slot.digest()
        |> Crypto.sign_with_node_key(1)

      assert true ==
               SummaryValidation.valid_signatures?(%{
                 slot
                 | validation_signatures: [{1, sig1}, {0, sig2}]
               })
    end
  end
end
