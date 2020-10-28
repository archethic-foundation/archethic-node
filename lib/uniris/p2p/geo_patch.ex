defmodule Uniris.P2P.GeoPatch do
  @moduledoc """
  Provide functions for Geographical Patching from IP address
   
  Each patch is represented by 3 digits in hexadecimal form (ie. AAA, F3C)
  """

  alias __MODULE__.GeoIP

  @doc """
  Get a patch from an IP address
  """
  @spec from_ip(:inet.ip_address()) :: binary()
  def from_ip({127, 0, 0, 1}) do
    list_char = Enum.concat([?0..?9, ?A..?F])
    Enum.take_random(list_char, 3) |> List.to_string()
  end

  def from_ip(ip) when is_tuple(ip) do
    {lat, lon} = GeoIP.get_coordinates(ip)
    compute_patch(lat, lon)
  end

  def diff(patch_a, patch_b) when is_binary(patch_a) and is_binary(patch_b) do
    patch_a = patch_a |> String.to_charlist() |> List.to_integer(16)
    patch_b = patch_b |> String.to_charlist() |> List.to_integer(16)
    abs(patch_a - patch_b)
  end

  defp compute_patch(lat, lon) do
    lat_sign = sign(lat)
    lon_sign = sign(lon)

    fdc = [lat / 90, lon / 180]

    sd =
      [(lat - lat_sign * 45) / 2, (lon - lon_sign * 90) / 2]
      |> resolve_with_sign([lat, lon])

    sdc = [List.first(sd) / 22.5, List.last(sd) / 45]

    td =
      [
        (List.first(sd) - lat_sign * 11.25) / 2,
        (List.last(sd) - lon_sign * 22.5) / 2
      ]
      |> resolve_with_sign(sd)

    tdc = [List.first(td) / 5.625, List.last(td) / 11.25]

    patch =
      [index_patch(fdc), index_patch(sdc), index_patch(tdc)]
      |> Enum.join("")

    patch
  end

  defp index_patch([f_i, s_i]) when f_i > 0.5 and f_i <= 1 and s_i < -0.5 and s_i >= -1, do: '0'
  defp index_patch([f_i, s_i]) when f_i > 0.5 and f_i <= 1 and s_i < 0 and s_i >= -0.5, do: '1'
  defp index_patch([f_i, s_i]) when f_i > 0.5 and f_i <= 1 and s_i < 0.5 and s_i >= 0, do: '2'
  defp index_patch([f_i, s_i]) when f_i > 0.5 and f_i <= 1 and s_i < 1 and s_i >= 0.5, do: '3'

  defp index_patch([f_i, s_i]) when f_i > 0 and f_i <= 0.5 and s_i < -0.5 and s_i >= -1, do: '4'
  defp index_patch([f_i, s_i]) when f_i > 0 and f_i <= 0.5 and s_i < 0 and s_i >= -0.5, do: '5'
  defp index_patch([f_i, s_i]) when f_i > 0 and f_i <= 0.5 and s_i < 0.5 and s_i >= 0, do: '6'
  defp index_patch([f_i, s_i]) when f_i > 0 and f_i <= 0.5 and s_i < 1 and s_i >= 0.5, do: '7'

  defp index_patch([f_i, s_i]) when f_i > -0.5 and f_i <= 0 and s_i < -0.5 and s_i >= -1, do: '8'
  defp index_patch([f_i, s_i]) when f_i > -0.5 and f_i <= 0 and s_i < 0 and s_i >= -0.5, do: '9'
  defp index_patch([f_i, s_i]) when f_i > -0.5 and f_i <= 0 and s_i < 0.5 and s_i >= 0, do: 'A'
  defp index_patch([f_i, s_i]) when f_i > -0.5 and f_i <= 0 and s_i < 1 and s_i >= 0.5, do: 'B'

  defp index_patch([f_i, s_i]) when f_i > -1 and f_i <= -0.5 and s_i < -0.5 and s_i >= -1, do: 'C'
  defp index_patch([f_i, s_i]) when f_i > -1 and f_i <= -0.5 and s_i < 0 and s_i >= -0.5, do: 'D'
  defp index_patch([f_i, s_i]) when f_i > -1 and f_i <= -0.5 and s_i < 0.5 and s_i >= 0, do: 'E'
  defp index_patch([f_i, s_i]) when f_i > -1 and f_i <= -0.5 and s_i < 1 and s_i >= 0.5, do: 'F'

  defp sign(number) when number < 0, do: -1
  defp sign(number) when number >= 0, do: 1

  defp resolve_with_sign([first, second], [first2, second2]) do
    [
      do_resolve_with_sign(first, first2),
      do_resolve_with_sign(second, second2)
    ]
  end

  defp do_resolve_with_sign(x1, x2) do
    if sign(x1) == sign(x2) do
      x1
    else
      x2 / 2
    end
  end
end
