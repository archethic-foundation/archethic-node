defmodule Distillery.Releases.Plugin.CookieLoader do
  @moduledoc false


  alias Distillery.Releases.Release
  alias Distillery.Releases.Profile
  alias Distillery.Releases.Plugin

  use Plugin

  @impl Plugin
  def before_assembly(release = %Release{profile: profile = %Profile{cookie: nil}}, _opts) do
    %{ release | profile: %{profile | cookie: get_cookie(release) } }
  end

  @impl Plugin
  def after_assembly(release = %Release{is_upgrade: true}, _opts) do
    # Do not change the cookie during upgrade
    release
  end

  @impl Plugin
  def after_assembly(release = %Release{is_upgrade: false, profile: profile = %Profile{cookie: cookie}}, _opts) do
    if persist_cookie?(profile) do
      profile
      |> get_cookie_filename()
      |> File.write!(Atom.to_string(cookie))
    end
    release
  end

  @impl Plugin
  def before_package(release, _opts), do: release

  @impl Plugin
  def after_package(release, _opts), do: release

  @impl Plugin
  def after_cleanup(release, _opts), do: release

  defp get_cookie(%Release{is_upgrade: true, profile: profile}) do
    case File.read(get_cookie_filename(profile)) do
      {:ok, cookie} ->
        cookie
      _ ->
        raise "Cookie not set for the upgrade"
      end
  end

  defp get_cookie(%Release{profile: profile}) do
    case File.read(get_cookie_filename(profile)) do
      {:ok, cookie} ->
        cookie
      _ ->
        :crypto.strong_rand_bytes(32) |> Base.encode16()
      end
  end

  defp get_cookie_filename(%Profile{output_dir: output_dir}) do
    Path.join([output_dir, "COOKIE"])
  end

  defp persist_cookie?(profile = %Profile{}) do
    cookie_filename = get_cookie_filename(profile)
    case File.read(cookie_filename) do
      {:ok, data} when data != "" ->
        false
      {:ok, ""} ->
          true
      _ ->
        true
      end
  end
end
