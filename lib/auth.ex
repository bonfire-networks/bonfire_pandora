defmodule Bonfire.PanDoRa.Auth do
  @moduledoc """
  Authentication boundary for Pandora access.

  This module centralises how Bonfire obtains Pandora auth material for a user,
  so callers do not need to know how Pandora authentication is implemented.

  At the moment the active runtime mechanism is the Pandora session cookie.
  """

  alias PanDoRa.API.Client

  @doc """
  Bootstraps the shadow Pandora user during Bonfire signup.

  Today this delegates to the existing password-based bootstrap flow. The goal
  is to keep that implementation detail behind a stable boundary.
  """
  def bootstrap_from_signup(user, password, _opts \\ []) do
    Client.sync_new_user_to_pandora(user, password)
  end

  @doc """
  Returns the currently stored Pandora session cookie for a user, if any.
  """
  def session_cookie(user_or_opts, opts \\ [])

  def session_cookie(user, opts) when is_map(user) do
    Client.get_session_cookie(nil, Keyword.put(opts, :current_user, user))
  end

  def session_cookie(opts, []) when is_list(opts) do
    Client.get_session_cookie(nil, opts)
  end

  def session_cookie(_, _), do: nil

  @doc """
  Returns auth headers for Pandora requests.

  Current active mechanism:
  1. Session cookie, if present
  2. `nil` if no Pandora auth material is available
  """
  def auth_headers(user_or_opts, opts \\ [])

  def auth_headers(user, opts) when is_map(user) do
    auth_headers(Keyword.put(opts, :current_user, user))
  end

  def auth_headers(opts, []) when is_list(opts) do
    case session_cookie(opts) do
      cookie when is_binary(cookie) and cookie != "" ->
        [{"cookie", "sessionid=#{cookie}"}]

      _ ->
        nil
    end
  end

  def auth_headers(_, _), do: nil
end
