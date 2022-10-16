defmodule ArchethicWeb.AEWebRootController do
  @moduledoc false

  alias ArchethicWeb.API.WebHostingController

  use ArchethicWeb, :controller

  def index(conn, params) do
    cache_headers = WebHostingController.get_cache_headers(conn)

    case WebHostingController.get_website(params, cache_headers) do
      {:ok, file_content, encodage, mime_type, cached?, etag} ->
        WebHostingController.send_response(conn, file_content, encodage, mime_type, cached?, etag)

      _ ->
        send_resp(conn, 404, "Not Found")
    end
  end
end
