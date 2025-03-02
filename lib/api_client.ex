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
  @metadata_keys ~w(director sezione edizione featuring)
  @metadata_fields ~w(director sezione edizione featuring)

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
    debug("Client.find called with opts: #{inspect(opts)}")

    range = calculate_range(opts)

    debug("Range calculated: #{inspect(range)}")

    items_payload = %{
      query: %{
        conditions: conditions,
        operator: "&"
      },
      # Request one extra
      range: [List.first(range), List.last(range) + 1],
      keys: Keyword.get(opts, :keys, ["title", "id"]),
      sort: Keyword.get(opts, :sort, [%{key: "title", operator: "+"}])
    }

    debug("Making request with payload: #{inspect(items_payload)}")

    case make_request("find", items_payload) do
      {:ok, %{"items" => items}} when is_list(items) ->
        requested_count = List.last(range) - List.first(range) + 1
        has_more = length(items) > requested_count
        items_to_return = if has_more, do: Enum.take(items, requested_count), else: items

        debug(
          "API returned #{length(items)} items, returning #{length(items_to_return)} items, has_more: #{has_more}"
        )

        {:ok,
         %{
           items: items_to_return,
           has_more: has_more
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
  Accepts optional page and per_page parameters for pagination.
  """
  @decorate time()
  def fetch_grouped_metadata(conditions \\ [], opts \\ []) do
    debug("Starting grouped metadata fetch")

    page = Keyword.get(opts, :page, 0)
    per_page = Keyword.get(opts, :per_page, 10)
    field = Keyword.get(opts, :field)

    start_idx = page * per_page
    end_idx = start_idx + per_page - 1

    debug(
      "fetching grouped metadata for field #{field} with page #{page} and per_page #{per_page}"
    )

    fields = if field, do: [field], else: @metadata_fields

    # Make a single request per field but in parallel
    tasks =
      fields
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
            # Use pagination range
            range: [start_idx, end_idx]
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
      Enum.zip(fields, tasks)
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
      range: [0, 10]
    }

    case make_request("find", payload) do
      {:ok, %{"items" => items}} when is_list(items) ->
        # API returns items in format [%{"name" => value, "items" => count}, ...]
        items

      _ ->
        []
    end
  end

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
        "format",
        "sezione",
        "edizione",
        "featuring"
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
  Gets a list by its ID.

  ## Parameters
    * `id` - The ID of the list to fetch

  Returns {:ok, list} on success where list contains id, section, and other properties
  Returns {:error, reason} on failure

  ## Examples
      iex> get_list("list123")
      {:ok, %{"id" => "list123", "section" => "personal", ...}}
  """
  def get_list(id) when is_binary(id) do
    case make_request("getList", %{id: id}) do
      {:ok, list} when is_map(list) ->
        debug(list, "List fetched")
        {:ok, list}

      other ->
        error(other, l("Could not fetch list"))
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

  @doc """
  Finds lists matching the given criteria.

  ## Options
    * `:page` - The page number (zero-based)
    * `:per_page` - Number of items per page
    * `:keys` - List of keys to return (featured, name, query, subscribed, user)
    * `:sort` - List of sort criteria
    * `:type` - Type of lists to fetch, one of:
      - `:featured` - Only featured lists
      - `:user` - Only user's personal lists
      - `:subscribed` - Only subscribed/favorite lists
  """
  def find_lists(opts \\ []) do
    range =
      if range = Keyword.get(opts, :range) do
        range
      else
        page = Keyword.get(opts, :page, 0)
        per_page = Keyword.get(opts, :per_page, 20)
        [page * per_page, (page + 1) * per_page - 1]
      end

    # Build conditions based on the type of lists we want
    conditions =
      case Keyword.get(opts, :type) do
        :featured ->
          [%{key: "status", operator: "==", value: "featured"}]

        :user ->
          [%{key: "user", operator: "==", value: get_auth_default_user()}]

        :subscribed ->
          [%{key: "subscribed", operator: "==", value: true}]

        :public ->
          [
            %{key: "status", operator: "==", value: "public"},
            %{key: "user", operator: "==", value: Keyword.get(opts, :user)}
          ]

        # Return all lists if no type specified
        _ ->
          []
      end

    payload = %{
      query: %{
        conditions: conditions,
        operator: "&"
      },
      range: range,
      keys: Keyword.get(opts, :keys, ["name", "id", "featured", "subscribed", "user"]),
      sort: Keyword.get(opts, :sort, [%{key: "name", operator: "+"}])
    }

    debug(payload, "Finding lists with payload")

    case make_request("findLists", payload) do
      {:ok, %{"items" => items}} when is_list(items) ->
        debug(items, "Received lists")
        {:ok, %{items: items, total: length(items)}}

      other ->
        error(other, l("Could not find any lists"))
    end
  end

  @doc """
  Edits a list with the given ID.

  ## Parameters
    * `:id` - The list ID to edit
    * `:name` - New name for the list
    * `:position` - New position for the list
    * `:poster_frames` - Array of {item, position} for poster frames
    * `:query` - New query for the list
    * `:status` - New status for the list (requires position to be set)
    * `:description` - Description of the list

  Returns {:ok, updated_list} on success, {:error, reason} on failure
  """
  def edit_list(id, params) when is_map(params) or is_list(params) do
    # Convert params to map if they're keyword list
    params = if is_list(params), do: Map.new(params), else: params

    # Ensure we have an ID
    params = Map.put(params, "id", id)

    case make_request("editList", params) do
      {:ok, list} when is_map(list) ->
        debug(list, "List updated")
        {:ok, list}

      other ->
        error(other, l("Could not update list"))
    end
  end

  @doc """
  Removes a list with the given ID.

  ## Parameters
    * `id` - The ID of the list to remove

  Returns {:ok, %{}} on success, {:error, reason} on failure
  """
  def remove_list(id) do
    case make_request("removeList", %{id: id}) do
      {:ok, _} ->
        debug("List #{id} removed successfully")
        {:ok, %{}}

      other ->
        error(other, l("Could not remove list"))
    end
  end

  @doc """
  Adds one or more items to a static list.

  ## Parameters
    * `list_id` - The ID of the list to add items to
    * `items` - List of item IDs to add
    * `query` - Query object for finding items (not implemented)

  Returns {:ok, %{}} on success, {:error, reason} on failure

  ## Examples
      iex> add_list_items("list123", items: ["item1", "item2"])
      {:ok, %{}}

      iex> add_list_items("list123", query: %{...})
      {:error, "Query-based addition not implemented"}
  """
  def add_list_items(list_id, opts \\ []) do
    cond do
      items = Keyword.get(opts, :items) ->
        payload = %{
          list: list_id,
          items: items
        }

        case make_request("addListItems", payload) do
          {:ok, _} ->
            debug("Items #{inspect(items)} added to list #{list_id}")
            {:ok, %{}}

          other ->
            error(other, l("Could not add items to list"))
        end

      Keyword.has_key?(opts, :query) ->
        {:error, l("Query-based addition not implemented")}

      true ->
        {:error, l("Either items or query must be provided")}
    end
  end

  @doc """
  Removes one or more items from a static list.

  ## Parameters
    * `list_id` - The ID of the list to remove items from
    * `items` - List of item IDs to remove
    * `query` - Query object for finding items to remove (not implemented)

  Returns {:ok, %{}} on success, {:error, reason} on failure

  ## Examples
      iex> remove_list_items("list123", items: ["item1", "item2"])
      {:ok, %{}}

      iex> remove_list_items("list123", query: %{...})
      {:error, "Query-based removal not implemented"}
  """
  def remove_list_items(list_id, opts \\ []) do
    cond do
      items = Keyword.get(opts, :items) ->
        payload = %{
          list: list_id,
          items: items
        }

        case make_request("removeListItems", payload) do
          {:ok, _} ->
            debug("Items #{inspect(items)} removed from list #{list_id}")
            {:ok, %{}}

          other ->
            error(other, l("Could not remove items from list"))
        end

      Keyword.has_key?(opts, :query) ->
        {:error, l("Query-based removal not implemented")}

      true ->
        {:error, l("Either items or query must be provided")}
    end
  end

  @doc """
  Creates a new list.

  ## Parameters
    * `params` - Map or keyword list of list properties:
      - `:name` - List name (optional, defaults to "Untitled")
      - `:description` - List description
      - `:items` - List of item IDs to add initially
      - `:query` - Query for dynamic lists
      - `:sort` - Sort criteria
      - `:type` - List type
      - `:view` - View settings

  Returns {:ok, list} on success where list contains id, name, and other properties
  Returns {:error, reason} on failure

  ## Examples
      iex> add_list(name: "My Favorites", description: "A collection of my favorite movies")
      {:ok, %{"id" => "123", "name" => "My Favorites", ...}}
  """
  def add_list(params \\ []) do
    # Convert params to map if they're keyword list
    params = if is_list(params), do: Map.new(params), else: params

    # Ensure name is present and properly formatted
    params =
      Map.update(params, "name", "Untitled", fn name ->
        name = if is_binary(name), do: String.trim(name), else: ""
        if name == "", do: "Untitled", else: name
      end)

    case make_request("addList", params) do
      {:ok, list} when is_map(list) ->
        debug(list, "List created")
        {:ok, list}

      other ->
        error(other, l("Could not create list"))
    end
  end

  @doc """
  Finds all items within a specific list.

  ## Parameters
    * `list_id` - The ID of the list to fetch items from
    * `opts` - Additional options:
      * `:page` - The page number (zero-based)
      * `:per_page` - Number of items per page
      * `:keys` - List of item properties to return
      * `:sort` - List of sort criteria

  Returns {:ok, %{items: items, total: total}} on success
  Returns {:error, reason} on failure

  ## Examples
      iex> find_list_items("list123", keys: ["title", "year"])
      {:ok, %{items: [%{"id" => "movie1", "title" => "Movie 1"}, ...], total: 10}}
  """
  def find_list_items(list_id, opts \\ []) do
    range =
      if range = Keyword.get(opts, :range) do
        range
      else
        page = Keyword.get(opts, :page, 0)
        per_page = Keyword.get(opts, :per_page, 20)
        [page * per_page, (page + 1) * per_page]
      end

    payload = %{
      query: %{
        conditions: [
          %{
            key: "list",
            operator: "==",
            value: list_id
          }
        ],
        operator: "&"
      },
      range: range,
      keys:
        Keyword.get(opts, :keys, [
          "title",
          "id",
          "item_id",
          "public_id",
          "director",
          "country",
          "year",
          "language",
          "duration"
        ]),
      sort: Keyword.get(opts, :sort, [%{key: "title", operator: "+"}])
    }

    case make_request("find", payload) do
      {:ok, %{"items" => items}} when is_list(items) ->
        debug(items, "List items fetched")
        {:ok, %{items: items, total: length(items)}}

      other ->
        error(other, l("Could not fetch list items"))
    end
  end

  @doc """
  Creates a new annotation for a movie

  ## Parameters
    * `data` - Map containing:
      * `:item` - item id (movie id)
      * `:layer` - annotation layer id
      * `:in` - in point in seconds
      * `:out` - out point in seconds
      * `:value` - annotation value (the note text)
  """
  def add_annotation(data) when is_map(data) do
    # Validate required fields
    required_fields = [:item, :layer, :in, :out, :value]

    if Enum.all?(required_fields, &Map.has_key?(data, &1)) do
      make_request("addAnnotation", data)
    else
      {:error, "Missing required fields"}
    end
  end

  @doc """
  Edits an existing annotation

  ## Parameters
    * `data` - Map containing:
      * `:id` - annotation id (required)
      * `:in` - in point in seconds (optional)
      * `:out` - out point in seconds (optional)
      * `:value` - annotation value/text (optional)

  ## Examples
      iex> edit_annotation(%{id: "annotation123", value: "Updated note text"})
      {:ok, %{"id" => "annotation123", ...}}
  """
  def edit_annotation(data) when is_map(data) do
    # Validate required fields
    if Map.has_key?(data, :id) do
      make_request("editAnnotation", data)
    else
      {:error, "Missing required id field"}
    end
  end

  @doc """
  Removes an annotation by its ID

  ## Parameters
    * `id` - The annotation ID to remove

  ## Examples
      iex> remove_annotation("annotation123")
      {:ok, %{}}
  """
  def remove_annotation(id) when is_binary(id) do
    make_request("removeAnnotation", %{id: id})
  end

  @doc """
  Edits metadata of a movie item

  ## Parameters
    * `data` - Map containing:
      * `:id` - The item id (required)
      * Additional key/value pairs for the fields to update

  ## Examples
      iex> edit_movie(%{id: "movie123", title: "New Title", year: "2023"})
      {:ok, %{title: "New Title", year: "2023"}}
  """
  def edit_movie(data) when is_map(data) do
    # Validate required fields
    if Map.has_key?(data, :id) do
      make_request("edit", data)
    else
      {:error, "Missing required field: id"}
    end
  end

  # Helper to conditionally add conditions based on options
  defp maybe_add_condition(conditions, opts, key, field) do
    case Keyword.get(opts, key) do
      nil -> conditions
      value -> [%{key: field, operator: "==", value: value} | conditions]
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
  defp process_field_values(values, field_type)
       when field_type in ~w(director sezione edizione featuring) do
    values
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.frequencies()
    |> Enum.map(fn {value, count} ->
      %{
        "name" => value,
        "items" => count
      }
    end)
    |> Enum.sort_by(& &1["name"])
  end

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
        # Increase connect timeout to 3s
        connect_options: [timeout: 3_000],
        # Increase receive timeout to 5s
        receive_timeout: 5_000,
        # Retry on network errors
        retry: :transient,
        # Try twice more on failure
        max_retries: 2
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
        maybe_return_data(decoded)

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

  defp calculate_range(opts) do
    if range = Keyword.get(opts, :range) do
      range
    else
      page = Keyword.get(opts, :page, 0)
      per_page = Keyword.get(opts, :per_page, 20)
      [page * per_page, (page + 1) * per_page]
    end
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
  defp maybe_sign_in_and_or_put_auth_cookie(req, _, "signin", _), do: req

  defp maybe_sign_in_and_or_put_auth_cookie(req, username, action, retry_count)
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

  defp maybe_sign_in_and_or_put_auth_cookie(req, _, _, _), do: req

  defp maybe_save_auth_cookie(headers, username, action) do
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

  def get_session_cookie(username) do
    Config.get([__MODULE__, :session_cookie, username], nil, :bonfire_pandora)
  end

  def get_auth_default_user do
    Config.get([__MODULE__, :username], nil, :bonfire_pandora)
  end

  defp get_auth_pw(username) do
    Config.get([__MODULE__, :password], nil, :bonfire_pandora)
  end

  defp get_auth_credentials(opts \\ []) do
    username = get_auth_default_user()
    {username, get_auth_pw(username)}
  end

  def get_pandora_url do
    Bonfire.Common.Config.get([__MODULE__, :pandora_url], "https://bff.matango.tv")
  end

  defp get_api_url do
    get_pandora_url() <> "/api/"
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
      {:ok, %{"items" => items}} when is_list(items) ->
        {:ok, items}

      error ->
        debug(error, "Error fetching annotations")
        error
    end
  end
end
