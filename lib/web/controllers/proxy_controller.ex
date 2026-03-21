defmodule Bonfire.PanDoRa.Web.ProxyController do
  @moduledoc """
  Proxies media requests (images, videos) to Pandora with the user's session cookie.

  Since Pandora requires authentication even for thumbnails and video streams,
  and the browser doesn't carry the Pandora session cookie (authentication is
  server-side), all media is fetched server-side and forwarded to the client.

  Video proxying currently favours a simple, known-good path for the first
  Bonfire/Pandora integration release: fetch upstream with auth and relay it
  directly. This keeps the controller aligned with the auth boundary while we
  stabilise playback.
  """
  use Bonfire.UI.Common.Web, :controller
  use Untangle
  alias Bonfire.PanDoRa.Auth
  alias PanDoRa.API.Client

  # 10 minutes
  @image_cache_ttl 1_000 * 60 * 10
  @video_cache_ttl 1_000 * 60 * 10
  @browser_image_max_age 600
  @browser_video_max_age 60
  @initial_video_range_end 262_143
  @max_video_range_size 1_048_576

  def proxy_image(conn, %{"path" => path}) when is_list(path) do
    if Enum.empty?(path) do
      conn |> put_status(400) |> text("Invalid path")
    else
      path_string = Enum.join(path, "/")
      cache_key = "pandora_image_#{path_string}"

      case Bonfire.Common.Cache.get!(cache_key) do
        {media_data, content_type} when is_binary(media_data) ->
          serve_buffered(conn, 200, media_data, content_type, "image/jpeg", @browser_image_max_age)

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
      query = conn.query_string |> to_string() |> String.trim()
      proxy_video_buffered(conn, path_string, query)
    end
  end

  # ── internals ────────────────────────────────────────────────────────────────

  # Builds the full Pandora URL for a given path segment.
  defp pandora_url(path, query \\ "")

  defp pandora_url(path, query) when is_binary(query) and query != "" do
    base = String.trim_trailing(Client.get_pandora_url() || "", "/")
    "#{base}/#{path}?#{query}"
  end

  defp pandora_url(path, _) do
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

            serve_buffered(conn, 200, body, ct, default_ct, @browser_image_max_age)

          {:ok, %Req.Response{status: status}} ->
            conn |> put_status(status) |> text("Pandora returned #{status}")

          {:error, reason} ->
            warn(reason, "[PanDoRa] proxy_buffered error")
            conn |> put_status(502) |> text("Proxy error")
        end
    end
  end

  defp proxy_video_buffered(conn, path_string, query_string \\ "")

  defp proxy_video_buffered(conn, path_string, query_string) do
    case get_auth_headers(conn) do
      nil ->
        conn |> put_status(403) |> text("Not connected to Pandora")

      req_headers ->
        url = pandora_url(path_string, query_string)
        # Clip requests (?t=in,out): let Pandora return the segment; avoid default Range that can confuse short responses.
        clip? = String.contains?(query_string, "t=")

        range_header =
          cond do
            clip? and match?([], get_req_header(conn, "range")) ->
              nil

            match?([_ | _], get_req_header(conn, "range")) ->
              get_req_header(conn, "range") |> hd() |> normalize_range_header()

            true ->
              "bytes=0-#{@initial_video_range_end}" |> normalize_range_header()
          end

        req_headers =
          if range_header do
            auth_headers_with_range(req_headers, range_header)
          else
            req_headers
          end

        case Req.get(url, headers: req_headers, decode_body: false, receive_timeout: 60_000) do
          {:ok, %Req.Response{status: status, body: body, headers: resp_headers}}
          when status in [200, 206] and is_binary(body) ->
            ct = upstream_content_type(resp_headers, guess_content_type(path_string, "video/mp4"))

            debug(%{
              path: path_string,
              requested_range: range_header,
              upstream_status: status,
              content_type: ct,
              body_size: byte_size(body)
            }, "[PanDoRa] proxy_video_buffered success")

            conn
            |> put_cache_headers(@browser_video_max_age)
            |> put_resp_content_type(ct)
            |> forward_headers(resp_headers, ~w(content-length content-range accept-ranges))
            |> ensure_accept_ranges()
            |> send_resp(status, body)

          {:ok, %Req.Response{status: status}} ->
            warn(%{path: path_string, requested_range: range_header, upstream_status: status},
              "[PanDoRa] proxy_video_buffered upstream status"
            )

            conn |> put_status(status) |> text("Pandora returned #{status}")

          {:error, reason} ->
            warn(reason, "[PanDoRa] proxy_video_buffered error")
            conn |> put_status(502) |> text("Proxy error")
        end
    end
  end

  defp serve_buffered(conn, status, data, content_type, default_ct, browser_max_age \\ nil) do
    ct = if is_binary(content_type) and content_type != "", do: content_type, else: default_ct

    {type, subtype} =
      case String.split(ct, "/", parts: 2) do
        [t, s] -> {t, s}
        _ -> {"application", "octet-stream"}
      end

    conn
    |> put_cache_headers(browser_max_age)
    |> put_resp_content_type(type, subtype)
    |> send_resp(status, data)
  end

  defp put_cache_headers(conn, nil), do: conn

  defp put_cache_headers(conn, max_age) when is_integer(max_age) and max_age >= 0 do
    put_resp_header(conn, "cache-control", "private, max-age=#{max_age}")
  end

  defp ensure_accept_ranges(conn) do
    case get_resp_header(conn, "accept-ranges") do
      [] -> put_resp_header(conn, "accept-ranges", "bytes")
      _ -> conn
    end
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

  defp upstream_content_type(resp_headers, default) do
    Enum.find_value(resp_headers, default, fn
      {key, value} when is_binary(key) ->
        if String.downcase(key) == "content-type" do
          case List.wrap(value) do
            [first | _] when is_binary(first) and first != "" -> first
            _ -> default
          end
        end

      _ ->
        nil
    end)
  end

  defp auth_headers_with_range(auth_headers, range_header) do
    auth_headers
    |> Enum.reject(fn {key, _} -> String.downcase(key) == "range" end)
    |> Kernel.++([{"range", range_header}])
  end

  defp normalize_range_header(range_header) when is_binary(range_header) do
    case Regex.run(~r/^bytes=(\d+)-(\d*)$/, range_header) do
      [_, start_s, ""] ->
        start_i = String.to_integer(start_s)
        stop_i = start_i + @max_video_range_size - 1
        "bytes=#{start_i}-#{stop_i}"

      [_, start_s, stop_s] ->
        start_i = String.to_integer(start_s)
        stop_i = String.to_integer(stop_s)
        max_stop = start_i + @max_video_range_size - 1

        if stop_i > max_stop do
          "bytes=#{start_i}-#{max_stop}"
        else
          range_header
        end

      _ ->
        range_header
    end
  end

  defp normalize_range_header(_), do: "bytes=0-#{@initial_video_range_end}"

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
