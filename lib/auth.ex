defmodule Bonfire.PanDoRa.Auth do
  @moduledoc """
  Authentication boundary for Pandora access.

  This module centralises how Bonfire obtains Pandora auth material for a user,
  so callers do not need to know how Pandora authentication is implemented.

  At the moment the active runtime mechanism is the Pandora session cookie.
  """

  alias Bonfire.Common.Config
  alias Bonfire.Common.Utils
  alias PanDoRa.API.Client
  use Bonfire.Common.Settings

  @doc """
  Bootstraps the shadow Pandora user during Bonfire signup.

  Today this delegates to the existing password-based bootstrap flow. The goal
  is to keep that implementation detail behind a stable boundary.
  """
  def bootstrap_from_signup(user, password, _opts \\ []) do
    Client.sync_new_user_to_pandora(user, password)
  end

  @doc """
  Returns the currently stored Pandora session cookie, if any.
  """
  def session_cookie(user_or_username_or_opts, opts \\ [])

  def session_cookie(user, opts) when is_map(user) do
    Settings.get([:bonfire_pandora, Client, :my_session_cookie], nil,
      current_user: user
    )
  end

  def session_cookie(username, opts) when is_binary(username) do
    case Utils.current_user(opts) do
      user when is_map(user) ->
        session_cookie(user, opts)

      _ ->
        Config.get([:bonfire_pandora, Client, :session_cookie, username], nil, :bonfire_pandora)
    end
  end

  def session_cookie(_unknown, opts) when is_list(opts) do
    case Utils.current_user(opts) do
      user when is_map(user) -> session_cookie(user, opts)
      _ -> nil
    end
  end

  def session_cookie(opts, []) when is_list(opts) do
    case Utils.current_user(opts) do
      user when is_map(user) -> session_cookie(user, opts)
      _ -> nil
    end
  end

  def session_cookie(_, _), do: nil

  @doc """
  Stores a Pandora session cookie for the given user or username.
  """
  def put_session_cookie(user_or_username_or_opts, cookie, opts \\ [])

  def put_session_cookie(user, cookie, opts) when is_map(user) do
    Settings.put([:bonfire_pandora, Client, :my_session_cookie], cookie,
      current_user: user
    )
  end

  def put_session_cookie(username, cookie, opts) when is_binary(username) do
    case Utils.current_user(opts) do
      user when is_map(user) ->
        put_session_cookie(user, cookie, opts)

      _ ->
        Config.put(
          [:bonfire_pandora, Client, :session_cookie],
          %{username => cookie},
          :bonfire_pandora
        )
    end
  end

  def put_session_cookie(_unknown, cookie, opts) when is_list(opts) do
    case Utils.current_user(opts) do
      user when is_map(user) -> put_session_cookie(user, cookie, opts)
      _ -> nil
    end
  end

  def put_session_cookie(opts, cookie, []) when is_list(opts) do
    case Utils.current_user(opts) do
      user when is_map(user) -> put_session_cookie(user, cookie, opts)
      _ -> nil
    end
  end

  def put_session_cookie(_, _, _), do: nil

  @doc """
  Clears the stored Pandora session cookie.
  """
  def clear_session(user_or_username_or_opts, opts \\ []) do
    put_session_cookie(user_or_username_or_opts, nil, opts)
  end

  @doc """
  Returns a lightweight auth state for the current Bonfire/Pandora integration.
  """
  def auth_state(user_or_opts, opts \\ [])

  def auth_state(user, opts) when is_map(user) do
    auth_state(Keyword.put(opts, :current_user, user))
  end

  def auth_state(opts, []) when is_list(opts) do
    if is_binary(session_cookie(opts)), do: :active, else: :missing_cookie
  end

  def auth_state(_, _), do: :missing_cookie

  @doc """
  Extracts the Pandora `sessionid` cookie value from response headers.
  """
  def extract_session_cookie(headers) when is_list(headers) do
    headers
    |> Enum.filter(fn {key, _} -> String.downcase(key) == "set-cookie" end)
    |> Enum.flat_map(fn {_, values} -> List.wrap(values) end)
    |> Enum.find_value(fn cookie_string ->
      case Regex.run(~r/sessionid=([^;]+)/, cookie_string) do
        [_, session_id] -> session_id
        _ -> nil
      end
    end)
  end

  def extract_session_cookie(_), do: nil

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
