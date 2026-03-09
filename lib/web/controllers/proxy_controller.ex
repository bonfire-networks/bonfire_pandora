defmodule Bonfire.PanDoRa.Web.ProxyController do
  @moduledoc """
  Proxies media requests (images, videos) to Pandora with the user's session cookie.

  Since Pandora requires authentication even for thumbnails and video streams,
  and the browser doesn't carry the Pandora session cookie (authentication is
  server-side), all media is fetched server-side and forwarded to the client.

  Video proxying supports HTTP Range requests so the player can seek correctly.
  Each Range request is small (a few MB), so buffering is acceptable.
  """
  use Bonfire.UI.Common.Web, :controller
  use Untangle
  alias PanDoRa.API.Client

  # 10 minutes
  @image_cache_ttl 1_000 * 60 * 10

  def proxy_image(conn, %{"path" => path}) when is_list(path) do
    if Enum.empty?(path) do
      conn |> put_status(400) |> text("Invalid path")
    else
      path_string = Enum.join(path, "/")
      cache_key = "pandora_image_#{path_string}"

      case Bonfire.Common.Cache.get!(cache_key) do
        {media_data, content_type} when is_binary(media_data) ->
          serve_buffered(conn, 200, media_data, content_type, "image/jpeg")

        _ ->
          proxy_buffered(conn, path_string, "image/jpeg", cache_key)
      end
    end
  end

  def proxy_video(conn, %{"path" => path}) when is_list(path) do
    if Enum.empty?(path) do
      conn |> put_status(400) |> text("Invalid path")
    else
      path_string = Enum.join(path, "/")
      proxy_range(conn, path_string)
    end
  end

  # ── internals ────────────────────────────────────────────────────────────────

  # Builds the full Pandora URL for a given path segment.
  defp pandora_url(path) do
    base = String.trim_trailing(Client.get_pandora_url() || "", "/")
    "#{base}/#{path}"
  end

  # Returns the stored Pandora session cookie for the current user.
  defp get_cookie(conn) do
    user = conn.assigns[:current_user]
    Client.get_session_cookie(nil, current_user: user)
  end

  # Fetches a resource, optionally caches it, and sends it to the client.
  defp proxy_buffered(conn, path_string, default_ct, cache_key) do
    with cookie when is_binary(cookie) <- get_cookie(conn) do
      url = pandora_url(path_string)
      req_headers = [{"cookie", "sessionid=#{cookie}"}]

      case Req.get(url, headers: req_headers, decode_body: false) do
        {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
          ct = guess_content_type(path_string, default_ct)

          if cache_key do
            Bonfire.Common.Cache.put(cache_key, {body, ct}, ttl: @image_cache_ttl)
          end

          serve_buffered(conn, 200, body, ct, default_ct)

        {:ok, %Req.Response{status: status}} ->
          conn |> put_status(status) |> text("Pandora returned #{status}")

        {:error, reason} ->
          warn(reason, "[PanDoRa] proxy_buffered error")
          conn |> put_status(502) |> text("Proxy error")
      end
    else
      _ -> conn |> put_status(403) |> text("Not connected to Pandora")
    end
  end

  # Proxies with Range support. Browser video players send Range requests for
  # seeking; each Range is a small chunk so buffering the partial response
  # is acceptable.
  defp proxy_range(conn, path_string) do
    with cookie when is_binary(cookie) <- get_cookie(conn) do
      url = pandora_url(path_string)

      req_headers =
        [{"cookie", "sessionid=#{cookie}"}] ++
          case get_req_header(conn, "range") do
            [range] -> [{"range", range}]
            _ -> []
          end

      case Req.get(url, headers: req_headers, decode_body: false, receive_timeout: 60_000) do
        {:ok, %Req.Response{status: status, body: body, headers: resp_headers}}
        when status in [200, 206] and is_binary(body) ->
          ct = guess_content_type(path_string, "video/mp4")

          conn
          |> put_resp_content_type(ct)
          |> forward_headers(resp_headers, ~w(content-range accept-ranges content-length))
          |> serve_buffered_raw(status, body)

        {:ok, %Req.Response{status: st}} ->
          conn |> put_status(st) |> text("Pandora returned #{st}")

        {:error, reason} ->
          warn(reason, "[PanDoRa] proxy_range error")
          conn |> put_status(502) |> text("Proxy error")
      end
    else
      _ -> conn |> put_status(403) |> text("Not connected to Pandora")
    end
  end

  defp serve_buffered(conn, status, data, content_type, default_ct) do
    ct = if is_binary(content_type) and content_type != "", do: content_type, else: default_ct

    {type, subtype} =
      case String.split(ct, "/", parts: 2) do
        [t, s] -> {t, s}
        _ -> {"application", "octet-stream"}
      end

    conn
    |> put_resp_content_type(type, subtype)
    |> send_resp(status, data)
  end

  defp serve_buffered_raw(conn, status, data) do
    send_resp(conn, status, data)
  end

  defp forward_headers(conn, resp_headers, allowed) do
    allowed_set = MapSet.new(Enum.map(allowed, &String.downcase/1))

    Enum.reduce(resp_headers, conn, fn {k, v}, acc ->
      if MapSet.member?(allowed_set, String.downcase(k)) do
        put_resp_header(acc, String.downcase(k), to_string(List.wrap(v) |> List.first()))
      else
        acc
      end
    end)
  end

  defp guess_content_type(path, default) do
    cond do
      String.ends_with?(path, ".webm") -> "video/webm"
      String.ends_with?(path, ".mp4") -> "video/mp4"
      String.ends_with?(path, ".jpg") or String.ends_with?(path, ".jpeg") -> "image/jpeg"
      String.ends_with?(path, ".png") -> "image/png"
      String.ends_with?(path, ".gif") -> "image/gif"
      true -> default
    end
  end
end
