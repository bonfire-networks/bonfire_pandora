defmodule Bonfire.PanDoRa.Web.ConnectPandoraController do
  @moduledoc """
  Handles "Connect to Pandora" from Settings: creates/syncs Pandora account
  with the given password and stores encrypted credentials for the current user.
  """
  use Bonfire.UI.Common.Web, :controller
  use Bonfire.Common.Localise
  alias PanDoRa.API.Client

  def create(conn, params) do
    user = current_user(conn) || conn.assigns[:current_user]
    password = get_password(params)

    cond do
      is_nil(user) ->
        conn
        |> put_flash(:error, l("You must be logged in to connect to Pandora."))
        |> redirect(to: redirect_back_after(conn))

      password in [nil, ""] ->
        conn
        |> put_flash(:error, l("Password is required."))
        |> redirect(to: redirect_back_after(conn))

      true ->
        case Client.sync_new_user_to_pandora(user, password) do
          {:ok, _} ->
            conn
            |> put_flash(:info, l("Connected to Pandora. Your credentials are stored securely."))
            |> redirect(to: redirect_back_after(conn))

          {:error, msg} when is_binary(msg) ->
            conn
            |> put_flash(:error, msg)
            |> redirect(to: redirect_back_after(conn))

          {:error, _} ->
            conn
            |> put_flash(:error, l("Could not connect to Pandora. Please try again."))
            |> redirect(to: redirect_back_after(conn))
        end
    end
  end

  defp get_password(%{"password" => p}) when is_binary(p), do: String.trim(p)
  defp get_password(%{"connect_pandora" => %{"password" => p}}) when is_binary(p), do: String.trim(p)
  defp get_password(_), do: nil

  defp redirect_back_after(conn) do
    get_session(conn, :redirect_after) || "/"
  end
end
