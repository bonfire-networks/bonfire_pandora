defmodule PanDoRa.API.Client do
  @moduledoc """
  Context module for interacting with the external API.
  """

  import Untangle
  use Bonfire.Common.Localise
  alias Bonfire.Common.Config

  @doc """
  Makes a request to the API with the given parameters.

  ## Parameters
    * opts - A keyword list of options:
      * action - The API action to perform (default: "find")
      * search_term - Optional search term
      * keys - List of keys to return in the response
      * range - Tuple of {start, end} for pagination
      * sort - List of maps with sorting instructions
      * conditions - Additional conditions to apply

  ## Examples
      iex> find(search_term: "example", keys: ["title", "id"])
      {:ok, %{...}}

      iex> find(action: "count", conditions: [%{key: "status", value: "active", operator: "="}])
      {:ok, %{count: 42}}

      # Custom query with multiple conditions
      {:ok, results} = find(action: "find",
        conditions: [
          %{key: "status", value: "active", operator: "="},
          %{key: "category", value: "books", operator: "="}
        ],
        keys: ["title", "id", "status", "category"],
        range: {0, 20},
        sort: [%{key: "created_at", operator: "-"}]
      )
  """
  def find(opts \\ []) do
    search_term = Keyword.get(opts, :search_term)
    keys = Keyword.get(opts, :keys, ["title", "id"])
    {starts, ends} = Keyword.get(opts, :range, {0, 10})
    sort = Keyword.get(opts, :sort, [%{key: "title", operator: "+"}])
    extra_conditions = Keyword.get(opts, :conditions, [])

    conditions = build_conditions(search_term) ++ extra_conditions

    payload = %{
      query: build_query(conditions),
      keys: keys,
      range: [starts, ends],
      sort: sort
    }

    make_request(opts[:action] || "find", payload)
  end

  def request(action \\ "find", payload \\ %{}, opts \\ []) do
    make_request(action, payload || %{})
  end

  defp build_conditions(nil), do: []

  defp build_conditions(search_term) when is_binary(search_term) do
    [%{key: "*", value: search_term, operator: "="}]
  end

  defp build_query([]), do: %{}
  defp build_query(conditions), do: %{conditions: conditions}

  @doc """
  Signs in a user with the given username and password.

  ## Parameters
  * username - The user's username
  * password - The user's password

  ## Returns
  * {:ok, %{"user"=>user} = data} - On successful sign-in
  * {:error, errors} - On failed sign-in, returns error map

  ## Examples
      iex> sign_in("johndoe", "password123")
      {:ok, %{id: 1, username: "johndoe", ...}}

      iex> sign_in("unknown", "wrongpassword")
      {:error, %{username: "Unknown Username"}}
  """
  def sign_in(username, password) do
    set_session_cookie(username, nil)

    payload = %{
      username: username,
      password: password
    }

    make_request("signin", payload)
  end

  def sign_in do
    case get_auth_credentials() do
      {username, password} when is_binary(username) and is_binary(password) ->
        sign_in(username, password)

      _ ->
        error(l("No username/password found"))
    end
  end

  defp make_request(action, payload, opts \\ []) do
    username = opts[:username] || get_auth_default_user()
    req = Req.new(url: get_api_url())

    req =
      case get_session_cookie(username) do
        nil -> req
        cookie -> Req.Request.put_header(req, "cookie", "sessionid=#{cookie}")
      end
      |> debug()

    form_data = %{
      action: action,
      data: Jason.encode!(payload)
    }

    case Req.post(req, form: form_data) do
      {:ok, %Req.Response{status: 200, body: body, headers: headers}} ->
        debug(body)

        set_cookie =
          if cookie = extract_session_cookie(headers) do
            set_session_cookie(username, cookie)
            nil
          else
            if action == "signin" do
              error(headers, l("No session cookie received"))
            end
          end

        maybe_return_data(body) || set_cookie || l("No data received fro API")

      {:ok, %Req.Response{status: 401}} ->
        error(l("Authentication failed"))

      {:ok, %Req.Response{status: status, body: body}} ->
        error(body, l("API request failed with code %{status}", status: status))

      {:error, error} ->
        error(error, l("API request failed"))
    end
  end

  defp maybe_return_data(%{"data" => %{"errors" => errors} = data}) do
    error(errors)
  end

  defp maybe_return_data(%{"data" => data, "status" => %{"code" => 200}}) do
    {:ok, data}
  end

  defp maybe_return_data(%{"data" => data, "status" => %{"code" => status, "text" => error}}) do
    error(
      data,
      l("API request failed with code %{code} and error: %{message}",
        code: status,
        message: error
      )
    )
  end

  defp maybe_return_data(%{"data" => data, "status" => %{"code" => status}}) do
    error(data, l("API request failed with code %{status}", status: status))
  end

  defp maybe_return_data(%{} = data) do
    {:ok, data}
  end

  defp maybe_return_data(nil) do
    nil
  end

  defp maybe_return_data(body) do
    error(body, l("API data not recognised"))
  end

  defp extract_session_cookie(headers) do
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

  defp set_session_cookie(username, cookie) do
    # TEMP: should store some other way?
    Config.put([__MODULE__, :session_cookie], %{username => cookie}, :bonfire_pandora)
  end

  defp get_session_cookie(username) do
    Config.get([__MODULE__, :session_cookie, username], nil, :bonfire_pandora)
  end

  defp get_api_url do
    Config.get([__MODULE__, :api_url], "https://0xdb.org/api/")
  end

  defp get_auth_default_user do
    Config.get([__MODULE__, :username], nil, :bonfire_pandora)
  end

  defp get_auth_credentials do
    {get_auth_default_user(), Config.get([__MODULE__, :password], nil, :bonfire_pandora)}
  end
end
