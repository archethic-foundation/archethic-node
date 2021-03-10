defmodule Uniris.P2P.Multiplexer.Demuxer do
  @moduledoc """
  Process responsible to demultiplex messages when they arrive and notify the receving handler
  """

  use GenServer

  alias Uniris.P2P.Transport

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    transport = Keyword.get(args, :transport)
    socket = Keyword.get(args, :socket)
    muxer_pid = Keyword.get(args, :muxer_pid)
    multiplexer_pid = Keyword.get(args, :multiplexer_pid)
    recv_handler = Keyword.get(args, :recv_handler)

    Task.start(fn ->
      Transport.read_from_socket(transport, socket, fn <<id::32, data::binary>> ->
        recv_handler.(id, data, muxer_pid: muxer_pid, multiplexer_pid: multiplexer_pid)
      end)
    end)

    {:ok, %{}}
  end

  # @spec decode_data(binary()) :: list(binary())
  # def decode_data(<<_stream_id::8, nb_messages::32, rest::binary>>) do
  #   do_demuxing(rest, nb_messages, [])
  # end

  # defp do_demuxing(
  #        <<id::32, message_size::32, message::binary-size(message_size), rest::binary>>,
  #        nb_messages,
  #        acc
  #      ) do
  #   do_demuxing(rest, nb_messages, [<<id::32, message::binary>> | acc])
  # end

  # defp do_demuxing(<<>>, nb_messages, acc) when length(acc) == nb_messages, do: acc
end
