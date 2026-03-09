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
  @video_cache_ttl 1_000 * 60 * 10
  @stream_timeout 60_000

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

  # Returns the auth header for the current user:
  # prefers Bearer token (pandora_token_oidc, never expires) over session cookie.
  defp get_auth_headers(conn) do
    user = conn.assigns[:current_user]
    opts = [current_user: user]

    case Client.get_bearer_token(opts) do
      bearer when is_binary(bearer) and bearer != "" ->
        [{"authorization", "Bearer #{bearer}"}]

      _ ->
        case Client.get_session_cookie(nil, opts) do
          cookie when is_binary(cookie) -> [{"cookie", "sessionid=#{cookie}"}]
          _ -> nil
        end
    end
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
  # seeking. We stream chunks through Bonfire as they arrive from Pandora
  # so playback can start quickly instead of waiting for the full body.
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
            proxy_streaming(conn, url, path_string, auth_headers, range_header, cache_key, started_at)
        end
    end
  end

  defp proxy_streaming(conn, url, path_string, auth_headers, range_header, cache_key, started_at) do
    ensure_httpc_started()

    headers =
      Enum.map(auth_headers ++ [{"range", range_header}], fn {k, v} ->
        {String.to_charlist(k), String.to_charlist(v)}
      end)

    case :httpc.request(
           :get,
           {String.to_charlist(url), headers},
           [timeout: @stream_timeout],
           [sync: false, stream: self(), body_format: :binary]
         ) do
      {:ok, request_id} ->
        stream_httpc_start(conn, request_id, path_string, range_header, cache_key, started_at)

      {:error, reason} ->
        warn(reason, "[PanDoRa] proxy_streaming start error")
        conn |> put_status(502) |> text("Proxy error")
    end
  end

  defp stream_httpc_start(conn, request_id, path_string, range_header, cache_key, started_at) do
    receive do
      {:http, {^request_id, stream_start, {status_line, resp_headers}}} ->
        status = extract_status_code(status_line, fallback_status(range_header))
        start_chunked_stream(conn, request_id, path_string, range_header, status, resp_headers, cache_key, started_at)

      {:http, {^request_id, stream_start, resp_headers}} ->
        status = fallback_status(range_header)
        start_chunked_stream(conn, request_id, path_string, range_header, status, resp_headers, cache_key, started_at)

      {:http, {^request_id, {{_http_vsn, status, _reason}, resp_headers, body}}} when is_binary(body) ->
        ct = guess_content_type(path_string, "video/mp4")

        debug(%{
          path: path_string,
          requested_range: range_header,
          upstream_status: status,
          content_type: ct,
          elapsed_ms: System.monotonic_time(:millisecond) - started_at,
          cache: "miss-buffered"
        }, "[PanDoRa] proxy_range success")

        if cache_key do
          Bonfire.Common.Cache.put(cache_key, {status, body, resp_headers}, ttl: @video_cache_ttl)
        end

        conn
        |> put_resp_content_type(ct)
        |> forward_headers(resp_headers, ~w(content-range accept-ranges content-length))
        |> serve_buffered_raw(status, body)

      {:http, {^request_id, {:error, reason}}} ->
        warn(reason, "[PanDoRa] proxy_streaming upstream error")
        conn |> put_status(502) |> text("Proxy error")
    after
      @stream_timeout ->
        warn(%{path: path_string, requested_range: range_header}, "[PanDoRa] proxy_streaming start timeout")
        conn |> put_status(504) |> text("Proxy timeout")
    end
  end

  defp start_chunked_stream(conn, request_id, path_string, range_header, status, resp_headers, cache_key, started_at) do
    ct = guess_content_type(path_string, "video/mp4")

    case conn
         |> put_resp_content_type(ct)
         |> forward_headers(resp_headers, ~w(content-range accept-ranges content-length))
         |> send_chunked(status) do
      {:ok, conn} ->
        debug(%{
          path: path_string,
          requested_range: range_header,
          upstream_status: status,
          content_type: ct,
          elapsed_ms: System.monotonic_time(:millisecond) - started_at,
          cache: "miss-stream"
        }, "[PanDoRa] proxy_range success")

        pump_httpc_chunks(conn, request_id, cache_key, status, resp_headers, [])

      {:error, reason} ->
        warn(reason, "[PanDoRa] send_chunked failed")
        conn |> put_status(502) |> text("Proxy error")
    end
  end

  defp pump_httpc_chunks(conn, request_id, cache_key, status, resp_headers, acc) do
    receive do
      {:http, {^request_id, stream, chunk}} when is_binary(chunk) ->
        next_acc =
          if cache_key do
            [acc, chunk]
          else
            acc
          end

        case chunk(conn, chunk) do
          {:ok, conn} ->
            pump_httpc_chunks(conn, request_id, cache_key, status, resp_headers, next_acc)

          {:error, reason} ->
            warn(reason, "[PanDoRa] chunk send failed")
            conn
        end

      {:http, {^request_id, stream_end, _trailers}} ->
        if cache_key do
          Bonfire.Common.Cache.put(
            cache_key,
            {status, IO.iodata_to_binary(acc), resp_headers},
            ttl: @video_cache_ttl
          )
        end

        conn

      {:http, {^request_id, {:error, reason}}} ->
        warn(reason, "[PanDoRa] proxy_streaming chunk error")
        conn
    after
      @stream_timeout ->
        warn("[PanDoRa] proxy_streaming chunk timeout")
        conn
    end
  end

  defp fallback_status(range_header) do
    if is_binary(range_header) and String.starts_with?(range_header, "bytes="), do: 206, else: 200
  end

  defp extract_status_code({_http_vsn, status, _reason}, fallback) when is_integer(status), do: status
  defp extract_status_code(_, fallback), do: fallback

  defp ensure_httpc_started do
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)
    :ok
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
