defmodule ArchEthic.P2P.Message.UnspentOutputList do
  @moduledoc """
  Represents a message with a list of unspent outputs
  """
  defstruct unspent_outputs: []

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  use ArchEthic.P2P.Message, message_id: 250

  @type t :: %__MODULE__{
          unspent_outputs: list(UnspentOutput.t())
        }

  def encode(%__MODULE__{unspent_outputs: unspent_outputs}) do
    unspent_outputs_bin =
      unspent_outputs
      |> Stream.map(&UnspentOutput.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_binary()

    <<Enum.count(unspent_outputs)::32, unspent_outputs_bin::binary>>
  end

  def decode(<<nb_unspent_outputs::32, rest::bitstring>>) do
    {unspent_outputs, rest} = deserialize_unspent_output_list(rest, nb_unspent_outputs, [])

    {
      %__MODULE__{
        unspent_outputs: unspent_outputs
      },
      rest
    }
  end

  defp deserialize_unspent_output_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_unspent_output_list(rest, nb_unspent_outputs, acc)
       when length(acc) == nb_unspent_outputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_unspent_output_list(rest, nb_unspent_outputs, acc) do
    {unspent_output, rest} = UnspentOutput.deserialize(rest)
    deserialize_unspent_output_list(rest, nb_unspent_outputs, [unspent_output | acc])
  end

  def process(%__MODULE__{}) do
  end
end
