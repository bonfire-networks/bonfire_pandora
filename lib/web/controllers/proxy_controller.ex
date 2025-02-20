defmodule Bonfire.PanDoRa.Web.ProxyController do
  use Bonfire.UI.Common.Web, :controller
  alias PanDoRa.API.Client

  def proxy_image(conn, %{"path" => path}) when is_list(path) do
    proxy_media(conn, path, "image/jpeg")
  end

  def proxy_video(conn, %{"path" => path}) when is_list(path) do
    proxy_media(conn, path, "video/mp4")
  end

  defp proxy_media(conn, path, default_content_type) do
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

        case Req.get(full_url,
               headers: [
                 {"cookie", "sessionid=#{cookie}"}
               ]
             ) do
          {:ok, %Req.Response{status: 200, body: media_data, headers: headers}} ->
            content_type =
              Enum.find_value(headers, default_content_type, fn
                {key, value} when is_binary(key) ->
                  if String.downcase(key) == "content-type", do: value
                _ -> nil
              end)

            # Ensure content_type is a string and split it
            content_type =
              cond do
                is_list(content_type) -> List.first(content_type)
                is_binary(content_type) -> content_type
                true -> default_content_type
              end

            # Split content type into main type and subtype
            {type, subtype} =
              case String.split(content_type || "", "/", parts: 2) do
                [t, s] -> {t, s}
                _ ->
                  [t, s] = String.split(default_content_type, "/", parts: 2)
                  {t, s}
              end

            # Set response content type and send
            conn
            |> Plug.Conn.put_resp_content_type(type, subtype)
            |> Plug.Conn.send_resp(200, media_data)

          {:ok, %Req.Response{status: status}} ->
            Plug.Conn.send_resp(conn, status, "Failed to fetch media")

          _error ->
            Plug.Conn.send_resp(conn, 500, "Internal server error")
        end

      {:error, _reason} ->
        Plug.Conn.send_resp(conn, 401, "Authentication failed")

      _other ->
        Plug.Conn.send_resp(conn, 500, "Unexpected error during authentication")
    end
  end
end
