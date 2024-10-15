defmodule PanDoRa.API.Client do
  @moduledoc """
  Context module for interacting with the external API.
  """

  import Untangle
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



  def sign_in() do
    case get_auth_credentials() do
      {username, password} when is_binary(username) and is_binary(password) ->
        sign_in(username, password)

      _ ->
        error("No username/password found")
    end
  end

 @doc """
  Signs in a user with the given username and password.

  ## Parameters
  * username - The user's username
  * password - The user's password

  ## Returns
  * :ok - On successful sign-in
  * {:error, error} - On failed sign-in, returns error

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

    case make_request("signin", payload) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp make_request(action, payload, opts \\ []) do
    username = opts[:username] || get_auth_default_user()
    url = get_api_url()
    req = Req.new(url: url)
    req = case get_session_cookie(username) do
      nil -> req
      cookie ->  Req.Request.put_header(req, "cookie", "sessionid=#{cookie}")
    end
    |> debug()

    form_data = %{
      action: action,
      data: Jason.encode!(payload)
    }

    case Req.post(req, form: form_data) do
      {:ok, %Req.Response{status: 200, body: body, headers: headers}} ->
        cookie = extract_session_cookie(headers)
        if cookie do 
          set_session_cookie(username, cookie)
          {:ok, body}
        else
          if action=="signin" do
            error(headers, "No session cookie received")
          else
            {:ok, body}
          end
        end
        
      {:ok, %Req.Response{status: 401}} ->
        {:error, :unauthorized}
      {:ok, %Req.Response{status: status, body: body}} ->
        error(body, "API request failed with status #{status}")
        {:error, :request_failed}
      {:error, error} ->
        error(error, "API request failed")
        {:error, :request_failed}
    end
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
    # TEMP: store some other way
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
