defmodule ArchethicWeb.AEWebRootController do
  @moduledoc false

  alias ArchethicWeb.API.WebHostingController

  use ArchethicWeb, :controller

  def index(conn, params = %{"url_path" => url_path}) do
    cache_headers = WebHostingController.get_cache_headers(conn)

    case WebHostingController.get_website(params, cache_headers) do
      {:ok, file_content, encodage, mime_type, cached?, etag} ->
        WebHostingController.send_response(conn, file_content, encodage, mime_type, cached?, etag)

      {:error, :not_found} ->
        # If file is not found, returning default file (url can be handled by index file)
        case url_path do
          [] ->
            send_resp(conn, 404, "Not Found")

          _path ->
            params = Map.put(params, "url_path", [])
            index(conn, params)
        end

      _ ->
        send_resp(conn, 404, "Not Found")
    end
  end
end
