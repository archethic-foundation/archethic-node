defmodule ArchEthicWeb.GraphQLSubscriptionCase do
  @moduledoc """
  This module defines the test case to be used by
  subscription tests.
  """
  use ExUnit.CaseTemplate
  alias Absinthe.Phoenix.SubscriptionTest
  alias Phoenix.ChannelTest, as: PhoenixChannelTest

  using do
    quote do
      import PhoenixChannelTest
      import ArchEthicWeb.GraphQLSubscriptionCase

      use Absinthe.Phoenix.SubscriptionTest, schema: ArchEthicWeb.GraphQLSchema

      defp get_socket do
        {:ok, socket} = PhoenixChannelTest.connect(ArchEthicWeb.UserSocket, %{}, %{})
        {:ok, socket} = SubscriptionTest.join_absinthe(socket)
        socket
      end

      defp subscribe(socket, query) do
        ref = push_doc(socket, query)
        assert_reply(ref, :ok, %{subscriptionId: subscription_id})

        subscription_id
      end
    end
  end
end
