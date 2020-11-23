defmodule Uniris.BeaconChain.GenICMP do
  @data <<0xDEADBEEF::size(32)>>
  def ping(addr) do
    {:ok, s} = open()

    data = @data

    req_echo(s, addr, data: data)

    case recv_echo(s) do
      {:ok, %{data: ^data}} = resp -> resp
      {:ok, other} -> {:error, other}
      _ -> {:error, :invalid_resp}
    end
  end

  def open, do: :socket.open(:inet, :raw, :icmp)

  def req_echo(socket, addr, opts \\ []) do
    data = Keyword.get(opts, :data, @data)
    id = Keyword.get(opts, :id, 0)
    seq = Keyword.get(opts, :seq, 0)

    sum = checksum(<<8, 0, 0::size(16), id, seq, data::binary>>)

    msg = <<8, 0, sum::binary, id, seq, data::binary>>

    :socket.sendto(socket, msg, %{family: :inet, port: 1, addr: addr})
  end

  def recv_echo(socket, timeout \\ 5000) do
    {:ok, data} = :socket.recv(socket, 0, [], timeout)

    <<_::size(160), pong::binary>> = data

    case pong do
      <<0, 0, _::size(16), id, seq, data::binary>> ->
        {:ok,
         %{
           id: id,
           seq: seq,
           data: data
         }}

      _ ->
        {:error, pong}
    end
  end

  defp checksum(bin), do: checksum(bin, 0)

  defp checksum(<<x::integer-size(16), rest::binary>>, sum), do: checksum(rest, sum + x)
  defp checksum(<<x>>, sum), do: checksum(<<>>, sum + x)

  defp checksum(<<>>, sum) do
    <<x::size(16), y::size(16)>> = <<sum::size(32)>>

    res = :erlang.bnot(x + y)

    <<res::big-size(16)>>
  end
end
