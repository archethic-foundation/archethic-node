defmodule UnirisCore.Mining.FeeTest do
  use ExUnit.Case

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias UnirisCore.Mining.Fee

  test "compute/1 should return 0 when transaction with type :node" do
    fee =
      Fee.compute(%Transaction{
        type: :node,
        address: "",
        timestamp: DateTime.utc_now(),
        data: %{},
        previous_public_key: "",
        previous_signature: "",
        origin_signature: ""
      })

    assert fee == 0.0
  end

  test "compute/1 should return 0 when transaction with type :node_shared_secrets" do
    fee =
      Fee.compute(%Transaction{
        type: :node_shared_secrets,
        address: "",
        timestamp: DateTime.utc_now(),
        data: %{},
        previous_public_key: "",
        previous_signature: "",
        origin_signature: ""
      })

    assert fee == 0.0
  end

  describe "distribute/5" do
    test "should distribute the fee across the invovled nodes based on the distribution rules" do
      fee = 0.5
      welcome_node = "503EF04022CDAA3F0F402A1C2524ED3782E09F228BC16DEB1766051C86880F8D"
      coordinator_node = "F35EB8260981AC5D8268B7B323277C8FB44D73B81DCC603B0E9CEB4B406A18AD"

      validation_nodes = [
        "5D0AE5A5B686030AD630119F3494B4852E3990BF196C117D574FD32BEB747FC7",
        "074CA174E4763A169F714C0D37187C5AC889683B4BBE9B0859C4073A690B7DF1"
      ]

      previous_storage_nodes = [
        "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23",
        "AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE",
        "4d75266a648f6d67576e6c77138c07042077b815fb5255d7f585cd36860da19e"
      ]

      rewards =
        Fee.distribute(
          fee,
          welcome_node,
          coordinator_node,
          validation_nodes,
          previous_storage_nodes
        )

      assert rewards == [
               %NodeMovement{
                 to: "503EF04022CDAA3F0F402A1C2524ED3782E09F228BC16DEB1766051C86880F8D",
                 amount: 0.0025
               },
               %NodeMovement{
                 to: "F35EB8260981AC5D8268B7B323277C8FB44D73B81DCC603B0E9CEB4B406A18AD",
                 amount: 0.0475
               },
               %NodeMovement{
                 to: "5D0AE5A5B686030AD630119F3494B4852E3990BF196C117D574FD32BEB747FC7",
                 amount: 0.1
               },
               %NodeMovement{
                 to: "074CA174E4763A169F714C0D37187C5AC889683B4BBE9B0859C4073A690B7DF1",
                 amount: 0.1
               },
               %NodeMovement{
                 to: "5EDA43AA8BBDAB66E4737989D44471F70FDEFD41D9E186507F27A61FA2170B23",
                 amount: 0.08333333333333333
               },
               %NodeMovement{
                 to: "AFC6C2DF93A524F3EE569745EE6F22131BB3F380E5121DDF730982DC7C1AD9AE",
                 amount: 0.08333333333333333
               },
               %NodeMovement{
                 to: "4d75266a648f6d67576e6c77138c07042077b815fb5255d7f585cd36860da19e",
                 amount: 0.08333333333333333
               }
             ]
    end

    test "should distribute the fee across the invovled nodes with additional rewards if not previous storage nodes" do
      fee = 1

      welcome_node = "503EF04022CDAA3F0F402A1C2524ED3782E09F228BC16DEB1766051C86880F8D"
      coordinator_node = "F35EB8260981AC5D8268B7B323277C8FB44D73B81DCC603B0E9CEB4B406A18AD"

      validation_nodes = [
        "5D0AE5A5B686030AD630119F3494B4852E3990BF196C117D574FD32BEB747FC7",
        "074CA174E4763A169F714C0D37187C5AC889683B4BBE9B0859C4073A690B7DF1"
      ]

      rewards =
        Fee.distribute(
          fee,
          welcome_node,
          coordinator_node,
          validation_nodes,
          []
        )

      assert [
               %NodeMovement{
                 to: "503EF04022CDAA3F0F402A1C2524ED3782E09F228BC16DEB1766051C86880F8D",
                 amount: 0.005
               },
               %NodeMovement{
                 to: "F35EB8260981AC5D8268B7B323277C8FB44D73B81DCC603B0E9CEB4B406A18AD",
                 amount: 0.26166666666666666
               },
               %NodeMovement{
                 to: "5D0AE5A5B686030AD630119F3494B4852E3990BF196C117D574FD32BEB747FC7",
                 amount: 0.3666666666666667
               },
               %NodeMovement{
                 to: "074CA174E4763A169F714C0D37187C5AC889683B4BBE9B0859C4073A690B7DF1",
                 amount: 0.3666666666666667
               }
             ] == rewards

      assert Enum.reduce(rewards, 0.0, &(&2 + &1.amount)) == fee
    end
  end
end
