defmodule Bonfire.PanDoRa.Web.ProxyController do
  use Bonfire.UI.Common.Web, :controller
  alias PanDoRa.API.Client
  
  # Add caching to reduce API calls
  @image_cache_ttl [expire: 1_000 * 60 * 10] # 10 minutes in milliseconds as expected by Cachex
  
  def proxy_image(conn, %{"path" => path}) when is_list(path) do
    # Check if we have a valid path before proceeding
    if Enum.empty?(path) do
      conn
      |> put_status(400)
      |> text("Invalid path")
    else
      # Implement file caching for images, as they're the most frequent resources
      path_string = Enum.join(path, "/")
      cache_key = "pandora_image_#{path_string}"
      
      case Bonfire.Common.Cache.get(cache_key) do
        # Return cached image if available
        {media_data, content_type} when is_binary(media_data) ->
          serve_media(conn, media_data, content_type, "image/jpeg")
          
        # Otherwise fetch and cache
        _ ->
          proxy_media(conn, path, "image/jpeg", true, cache_key)
      end
    end
  end

  def proxy_video(conn, %{"path" => path}) when is_list(path) do
    # Check if we have a valid path before proceeding
    if Enum.empty?(path) do
      conn
      |> put_status(400)
      |> text("Invalid path")
    else
      proxy_media(conn, path, "video/mp4", false, nil)
    end
  end

  defp proxy_media(conn, path, default_content_type, should_cache, cache_key) do
    # Join path parts to form the complete path
    path = Enum.join(path, "/")

    # Try to authenticate, handle potential failures
    case Client.sign_in() do
      {:ok, _} ->
        # Get the full Pandora URL and make the request
        pandora_url = Client.get_pandora_url()
        full_url = Path.join(pandora_url, path)

        # Get authentication credentials
        username = Client.get_auth_default_user()
        cookie = Client.get_session_cookie(username)

        case fetch_media(full_url, cookie) do
          {:ok, media_data, content_type} when is_binary(media_data) ->
            # Cache the result if requested
            if should_cache && cache_key do
              Bonfire.Common.Cache.put(cache_key, {media_data, content_type}, @image_cache_ttl)
            end
            
            serve_media(conn, media_data, content_type, default_content_type)

          {:error, status} ->
            conn |> put_status(status) |> text("Failed to fetch media")
            
          _ ->
            conn |> put_status(500) |> text("Unexpected media fetch error")
        end

      {:error, _reason} ->
        conn |> put_status(401) |> text("Authentication failed")

      _other ->
        conn |> put_status(500) |> text("Unexpected error during authentication")
    end
  end
  
  # Extract the media fetching logic for reuse
  defp fetch_media(url, cookie) do
    case Req.get(url,
           headers: [
             {"cookie", "sessionid=#{cookie}"}
           ]
         ) do
      {:ok, %Req.Response{status: 200, body: media_data, headers: headers}} ->
        content_type =
          Enum.find_value(headers, "application/octet-stream", fn
            {key, value} when is_binary(key) ->
              if String.downcase(key) == "content-type", do: value

            _ ->
              nil
          end)

        # Ensure content_type is a string
        content_type =
          cond do
            is_list(content_type) -> List.first(content_type)
            is_binary(content_type) -> content_type
            true -> "application/octet-stream"
          end
          
        {:ok, media_data, content_type}

      {:ok, %Req.Response{status: status}} ->
        {:error, status}

      _error ->
        {:error, 500}
    end
  end
  
  # Serve the media with proper content type
  defp serve_media(conn, media_data, content_type, default_content_type) do
    if not is_binary(media_data) do
      # Handle invalid media data
      conn
      |> put_status(500)
      |> text("Invalid media data")
    else
      # Make sure we have a valid content type
      content_type = if is_binary(content_type), do: content_type, else: default_content_type
    
      # Split content type into main type and subtype
      {type, subtype} =
        case String.split(content_type || "", "/", parts: 2) do
          [t, s] when t != "" and s != "" ->
            {t, s}
  
          _ ->
            # Fallback to default content type
            case String.split(default_content_type, "/", parts: 2) do
              [t, s] when t != "" and s != "" -> {t, s}
              _ -> {"application", "octet-stream"} # Last resort fallback
            end
        end
  
      # Set response content type and send
      conn
      |> put_resp_content_type(type, subtype)
      |> send_resp(200, media_data)
    end
  end
end
