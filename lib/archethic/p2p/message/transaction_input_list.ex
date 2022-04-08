defmodule ArchEthic.P2P.Message.TransactionInputList do
  @moduledoc """
  Represents a message with a list of transaction inputs
  """
  defstruct inputs: []

  alias ArchEthic.TransactionChain.TransactionInput

  use ArchEthic.P2P.Message, message_id: 244

  @type t() :: %__MODULE__{
          inputs: list(TransactionInput.t())
        }

  def encode(%__MODULE__{inputs: inputs}) do
    inputs_bin =
      inputs
      |> Stream.map(&TransactionInput.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    <<length(inputs)::16, inputs_bin::binary>>
  end

  def decode(<<nb_inputs::16, rest::bitstring>>) do
    {inputs, rest} = deserialize_transaction_inputs(rest, nb_inputs, [])

    {%__MODULE__{
       inputs: inputs
     }, rest}
  end

  defp deserialize_transaction_inputs(rest, 0, _acc), do: {[], rest}

  defp deserialize_transaction_inputs(rest, nb_inputs, acc) when length(acc) == nb_inputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_transaction_inputs(rest, nb_inputs, acc) do
    {input, rest} = TransactionInput.deserialize(rest)
    deserialize_transaction_inputs(rest, nb_inputs, [input | acc])
  end

  def process(%__MODULE__{}) do
  end
end
