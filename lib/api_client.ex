defmodule PanDoRa.API.Client do
  @moduledoc """
  Optimized API client implementation for fetching and caching metadata
  """

  use Untangle
  use Bonfire.Common.Localise
  alias Bonfire.Common.Config
  alias Bonfire.Common.Cache

  # Cache TTL of 1 hour
  @cache_ttl :timer.hours(1)
  @metadata_keys ~w(director country year language)
  @metadata_fields ~w(director country year language)

  @doc """
  Basic find function that matches the API's find endpoint functionality with pagination support

  ## Options
    * `:page` - The page number (zero-based)
    * `:per_page` - Number of items per page
    * `:keys` - List of keys to return in the response
    * `:sort` - List of sort criteria
    * `:conditions` - List of search conditions
    * `:total` - Whether to include total count in response
  """
  def find(opts \\ []) do
    conditions = Keyword.get(opts, :conditions, [])

    # Then get paginated items
    range =
      if range = Keyword.get(opts, :range) do
        range
      else
        page = Keyword.get(opts, :page, 0)
        per_page = Keyword.get(opts, :per_page, 20)
        [page * per_page, (page + 1) * per_page - 1]
      end

    items_payload = %{
      query: %{
        conditions: conditions,
        operator: "&"
      },
      range: range,
      keys: Keyword.get(opts, :keys, ["title", "id"]),
      sort: Keyword.get(opts, :sort, [%{key: "title", operator: "+"}])
    }

    case make_request("find", items_payload) do
      {:ok, %{"items" => items}} when is_list(items) ->
        {:ok,
         %{
           items: items,
           total: length(items),
           has_more: false
         }}

      other ->
        error(other, l("Could not find anything"))
    end
  end

  @doc """
  Helper function to calculate total pages
  """
  def calculate_total_pages(total_items, per_page)
      when is_integer(total_items) and is_integer(per_page) do
    ceil(total_items / per_page)
  end

  def calculate_total_pages(_, _), do: 1

  @doc """
  Fetches metadata efficiently using parallel requests and caching
  """
  def fetch_all_metadata(conditions \\ []) do
    cache_key = "pandora_metadata_#{:erlang.phash2(conditions)}"

    case Cache.get(cache_key) do
      nil ->
        # Fetch metadata for each field in parallel
        tasks =
          @metadata_keys
          |> Enum.map(fn field ->
            Task.async(fn ->
              fetch_field_metadata(field, conditions)
            end)
          end)

        # Wait for all tasks with timeout
        results = Task.await_many(tasks, 30_000)

        # Combine results
        metadata =
          results
          |> Enum.zip(@metadata_keys)
          |> Enum.reduce(%{}, fn {result, key}, acc ->
            Map.put(acc, "#{key}s", result)
          end)

        # Cache the results
        Cache.put(cache_key, metadata, ttl: @cache_ttl)
        {:ok, metadata}

      cached ->
        {:ok, cached}
    end
  end

  @doc """
  Fetches metadata with the current search conditions
  """
  @decorate time()
  def fetch_metadata(conditions, opts \\ []) do
    # High limit to get comprehensive data
    limit = Keyword.get(opts, :limit, 20)

    tasks =
      @metadata_keys
      |> Enum.map(fn field ->
        Task.async(fn ->
          fetch_field_metadata(field, conditions, limit)
        end)
      end)

    results = Task.await_many(tasks, 10_000)

    metadata =
      results
      |> Enum.zip(@metadata_keys)
      |> Enum.reduce(%{}, fn {result, key}, acc ->
        processed_results = process_metadata_field(result, key)
        Map.put(acc, "#{key}s", processed_results)
      end)

    {:ok, metadata}
  end

  @doc """
  Fetches grouped metadata for filters using the find endpoint with group parameter.
  """
  @decorate time()
  def fetch_grouped_metadata(conditions \\ []) do
    debug("Starting grouped metadata fetch")

    # Make a single request per field but in parallel
    tasks =
      @metadata_fields
      |> Enum.map(fn field ->
        Task.async(fn ->
          # Build query for each field
          payload = %{
            query: %{
              conditions: conditions,
              operator: "&"
            },
            group: field,
            # Sort by count descending
            sort: [%{key: "items", operator: "-"}],
            # Get top 20 items (0-19)
            range: [0, 19]
          }

          debug("Making request for field #{field}")
          result = make_request("find", payload)
          debug(result, "Got result for field #{field}")

          case result do
            {:ok, %{"items" => items}} when is_list(items) ->
              {field, items}

            _ ->
              {field, []}
          end
        end)
      end)

    # Wait for all requests with a reasonable timeout
    results = Task.yield_many(tasks, 5000)

    metadata =
      Enum.zip(@metadata_fields, tasks)
      |> Map.new(fn {field, task} ->
        case Enum.find(results, fn {t, _} -> t.ref == task.ref end) do
          {_, {:ok, {^field, items}}} ->
            debug("Successfully got #{length(items)} items for #{field}")
            {field, items}

          _ ->
            debug("Failed or timeout getting items for #{field}")
            {field, []}
        end
      end)

    {:ok, metadata}
  end

  @doc """
  Fetches grouped values for a single metadata field.
  """
  def fetch_grouped_field(field, conditions) when field in @metadata_fields do
    # Build the query payload according to API docs
    payload = %{
      query: %{
        conditions: conditions,
        # Default to AND operator
        operator: "&"
      },
      # Group results by the specified field
      group: field,
      # Sort by number of items descending
      sort: [%{key: "items", operator: "-"}],
      # Get up to 1000 grouped results
      range: [0, 20]
    }

    case make_request("find", payload) do
      {:ok, %{"items" => items}} when is_list(items) ->
        # API returns items in format [%{"name" => value, "items" => count}, ...]
        items

      _ ->
        []
    end
  end

  @doc """
  Converts a regular ID to the 0x-prefixed format required by the get endpoint.
  """

  # def format_movie_id(id) when is_binary(id) do
  #   case id do
  #     "0x" <> _ -> id
  #     id -> "0x#{String.upcase(id)}"
  #   end
  # end

  def get_movie(movie_id) do
    # Convert the ID to the required format
    # formatted_id = format_movie_id(movie_id)

    payload = %{
      id: movie_id,
      keys: [
        "title",
        "id",
        "director",
        "country",
        "year",
        "language",
        "duration",
        "hue",
        "saturation",
        "lightness",
        "volume",
        "runtime",
        "color",
        "sound",
        "writer",
        "producer",
        "cinematographer",
        "editor",
        "actor",
        "productionCompany",
        "genre",
        "keyword",
        "summary",
        "stream",
        "streams",
        "rightsLevels",
        "fps",
        "resolution",
        "codec",
        "bitrate",
        "filesize",
        "format"
      ]
    }

    case make_request("get", payload) do
      {:ok, %{} = data} ->
        debug(data, "Movie data retrieved")
        {:ok, data}

      error ->
        debug(error, "Error retrieving movie")
        error
    end
  end

  @doc """
  Makes an init request to get site configuration and user data.
  Returns `{:ok, data}` where data contains site and user information.
  """
  def init(opts \\ []) do
    case make_request("init", %{}, opts) do
      {:ok, %{"site" => _site, "user" => _user} = data} ->
        {:ok, data}

      error ->
        error(error, "Could not initialize API client")
    end
  end

  # Process each metadata field according to its structure
  defp process_metadata_field(items, field) do
    items
    |> Enum.flat_map(fn item ->
      case Map.get(item, field) do
        values when is_list(values) -> values
        value when is_binary(value) or is_integer(value) -> [value]
        nil -> []
      end
    end)
    |> process_field_values(field)
  end

  # Process specific fields with custom logic
  defp process_field_values(values, "year") do
    values
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.map(fn {year, count} ->
      %{"name" => to_string(year), "items" => count}
    end)
    |> Enum.sort_by(fn %{"name" => year} -> year end, :desc)
  end

  defp process_field_values(values, "language") do
    values
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.frequencies()
    |> Enum.map(fn {lang, count} ->
      %{"name" => lang, "items" => count}
    end)
    |> Enum.sort_by(fn %{"items" => count, "name" => name} -> {-count, name} end)
  end

  defp process_field_values(values, "country") do
    values
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.frequencies()
    |> Enum.map(fn {country, count} ->
      %{"name" => country, "items" => count}
    end)
    |> Enum.sort_by(fn %{"items" => count, "name" => name} -> {-count, name} end)
  end

  defp process_field_values(values, "director") do
    values
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.frequencies()
    |> Enum.map(fn {name, count} ->
      %{"name" => name, "items" => count}
    end)
    |> Enum.sort_by(fn %{"items" => count, "name" => name} -> {-count, name} end)
  end

  @decorate time()
  defp fetch_field_metadata(field, conditions, limit \\ 1000) do
    payload = %{
      query: %{
        conditions: conditions,
        # Default to AND operator
        operator: "&"
      },
      keys: [field],
      group_by: [
        %{
          key: field,
          sort: [%{key: "items", operator: "-"}],
          limit: limit
        }
      ]
    }

    debug(payload, "Making metadata request for #{field} with payload")

    case make_request("find", payload) do
      {:ok, %{"items" => items}} when is_list(items) ->
        items
        |> Enum.map(fn item ->
          %{"name" => Map.get(item, "name", ""), "items" => Map.get(item, "items", 0)}
        end)

      _ ->
        []
    end
  end

  @doc """
  Makes a request to the API endpoint
  """
  @decorate time()
  def make_request(endpoint, payload, opts \\ [], retry_count \\ 0) do
    debug(payload, "Making request to #{endpoint} with payload")
    api_url = get_api_url()
    username = opts[:username] || get_auth_default_user()

    req =
      Req.new(
        url: api_url,
        # Reduce timeout to 1.5s
        connect_options: [timeout: 1_500],
        # Reduce timeout to 3s
        receive_timeout: 3_000,
        # Retry on network errors
        retry: :transient,
        # Try once more on failure
        max_retries: 1
      )
      |> maybe_sign_in_and_or_put_auth_cookie(username, endpoint, retry_count)

    case Req.post(req,
           form: %{
             action: endpoint,
             data: Jason.encode!(payload)
           }
         ) do
      {:ok, %Req.Response{status: 200, headers: headers, body: body}} ->
        debug(body, label: "API Response (raw)")

        save_cookie = maybe_save_auth_cookie(headers, username, endpoint)

        maybe_return_data(body) || save_cookie || error(l("No data received from API"))

      {:ok, %Req.Response{status: 401}} ->
        error(l("Authentication failed"))

      {:ok, %Req.Response{status: status} = res} ->
        error(res, l("API request failed with status %{status}", status: status))

      {:error, %Req.TransportError{reason: :timeout}} ->
        # Only retry once more on timeout
        if retry_count < 1 do
          debug("Retrying request after timeout")
          make_request(endpoint, payload, opts, retry_count + 1)
        else
          error(l("API request timed out"))
        end

      other ->
        error(other, l("API request failed"))
    end
  end

  defp maybe_return_data(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        maybe_return_data(body)

      {:error, reason} ->
        error(reason, l("API JSON decode error"))
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

    make_request("signin", payload, username: username)
  end

  def sign_in(opts \\ []) do
    case get_auth_credentials(opts) do
      {username, password} when is_binary(username) and is_binary(password) ->
        sign_in(username, password)

      _ ->
        error(l("No username/password found"))
    end
  end

  # avoid looping
  def maybe_sign_in_and_or_put_auth_cookie(req, _, "signin", _), do: req

  def maybe_sign_in_and_or_put_auth_cookie(req, username, action, retry_count)
      when is_binary(username) do
    case get_session_cookie(username) do
      nil ->
        with {:ok, _} <- sign_in(username, get_auth_pw(username)) do
          if retry_count < 1 do
            maybe_sign_in_and_or_put_auth_cookie(req, username, action, retry_count + 1)
          else
            debug("skip auth because failed once")
            req
          end
        else
          auth_failed ->
            warn(auth_failed, "Could not authenticate, continue as guest")
            req
        end

      cookie ->
        Req.Request.put_header(req, "cookie", "sessionid=#{cookie}")
        |> debug()
    end
  end

  def maybe_sign_in_and_or_put_auth_cookie(req, _, _, _), do: req

  def maybe_save_auth_cookie(headers, username, action) do
    if cookie = extract_session_cookie(headers) do
      set_session_cookie(username, cookie)
      nil
    else
      if action == "signin" do
        error(headers, l("No session cookie received"))
      end
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
    # TEMP: should store some other way?
    Config.put([__MODULE__, :session_cookie], %{username => cookie}, :bonfire_pandora)
  end

  defp get_session_cookie(username) do
    Config.get([__MODULE__, :session_cookie, username], nil, :bonfire_pandora)
  end

  defp get_auth_default_user do
    Config.get([__MODULE__, :username], nil, :bonfire_pandora)
  end

  defp get_auth_pw(username) do
    Config.get([__MODULE__, :password], nil, :bonfire_pandora)
  end

  defp get_auth_credentials(opts \\ []) do
    username = get_auth_default_user()
    {username, get_auth_pw(username)}
  end

  defp get_api_url do
    Bonfire.Common.Config.get([__MODULE__, :api_url], "https://0xdb.org/api/")
  end

  @doc """
  Basic test function for annotations following API structure
  """
  def fetch_annotations(movie_id) do
    data = %{
      itemsQuery: %{
        conditions: [
          %{
            key: "id",
            operator: "==",
            value: movie_id
          }
        ]
      },
      query: %{
        conditions: [
          %{
            key: "layer",
            operator: "==",
            # Note: the database showed lowercase "publicnotes"
            value: "publicnotes"
          }
        ]
      },
      keys: [],
      range: [0, 99999]
    }

    case make_request("findAnnotations", data) do
      {:ok, response} ->
        {:ok, response}

      error ->
        debug(error, "Error fetching annotations")
        error
    end
  end
end
