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
  alias Bonfire.PanDoRa.Auth
  alias PanDoRa.API.Client

  # 10 minutes
  @image_cache_ttl 1_000 * 60 * 10
  @video_cache_ttl 1_000 * 60 * 10

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

  defp get_auth_headers(conn) do
    Auth.auth_headers(conn.assigns[:current_user])
  end

  # Fetches a resource, optionally caches it, and sends it to the client.
  defp proxy_buffered(conn, path_string, default_ct, cache_key) do
    case get_auth_headers(conn) do
      nil ->
        conn |> put_status(403) |> text("Not connected to Pandora")

      req_headers ->
        url = pandora_url(path_string)

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
    end
  end

  # Proxies with Range support. Browser video players send Range requests for
  # seeking. We use a single buffered request (Req) per range; the first
  # request (bytes=0-1MB) is cached so repeat loads are fast.
  defp proxy_range(conn, path_string) do
    case get_auth_headers(conn) do
      nil ->
        conn |> put_status(403) |> text("Not connected to Pandora")

      auth_headers ->
        url = pandora_url(path_string)
        started_at = System.monotonic_time(:millisecond)

        range_header =
          case get_req_header(conn, "range") do
            [range] -> range
            _ -> "bytes=0-1048575"
          end

        cache_key = video_cache_key(path_string, range_header)

        case cache_key && Bonfire.Common.Cache.get!(cache_key) do
          {status, body, resp_headers} when status in [200, 206] and is_binary(body) ->
            ct = guess_content_type(path_string, "video/mp4")

            debug(%{
              path: path_string,
              requested_range: range_header,
              upstream_status: status,
              content_type: ct,
              elapsed_ms: System.monotonic_time(:millisecond) - started_at,
              cache: "hit"
            }, "[PanDoRa] proxy_range success")

            conn
            |> put_resp_content_type(ct)
            |> forward_headers(resp_headers, ~w(content-range accept-ranges content-length))
            |> serve_buffered_raw(status, body)

          _ ->
            proxy_range_buffered(conn, url, path_string, auth_headers, range_header, cache_key, started_at)
        end
    end
  end

  defp proxy_range_buffered(conn, url, path_string, auth_headers, range_header, cache_key, started_at) do
    req_headers = auth_headers ++ [{"range", range_header}]

    case Req.get(url, headers: req_headers, decode_body: false, receive_timeout: 60_000) do
      {:ok, %Req.Response{status: status, body: body, headers: resp_headers}}
      when status in [200, 206] and is_binary(body) ->
        ct = guess_content_type(path_string, "video/mp4")

        if cache_key do
          Bonfire.Common.Cache.put(cache_key, {status, body, resp_headers}, ttl: @video_cache_ttl)
        end

        debug(%{
          path: path_string,
          requested_range: range_header,
          upstream_status: status,
          content_type: ct,
          elapsed_ms: System.monotonic_time(:millisecond) - started_at,
          cache: "miss"
        }, "[PanDoRa] proxy_range success")

        conn
        |> put_resp_content_type(ct)
        |> forward_headers(resp_headers, ~w(content-range accept-ranges content-length))
        |> serve_buffered_raw(status, body)

      {:ok, %Req.Response{status: st}} ->
        warn(%{
          path: path_string,
          requested_range: range_header,
          upstream_status: st,
          elapsed_ms: System.monotonic_time(:millisecond) - started_at
        }, "[PanDoRa] proxy_range upstream status")

        conn |> put_status(st) |> text("Pandora returned #{st}")

      {:error, reason} ->
        warn(reason, "[PanDoRa] proxy_range error")
        conn |> put_status(502) |> text("Proxy error")
    end
  end

  defp video_cache_key(path_string, range_header) do
    case Regex.run(~r/^bytes=(\d+)-(\d+)$/, range_header) do
      [_, start_s, stop_s] ->
        start_i = String.to_integer(start_s)
        stop_i = String.to_integer(stop_s)

        if start_i == 0 and stop_i - start_i <= 8_388_608 do
          "pandora_video_#{path_string}_#{start_i}_#{stop_i}"
        end

      _ ->
        nil
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
