defmodule PanDoRa.API.Client do
  @moduledoc """
  Optimized API client implementation for fetching and caching metadata
  """

  use Untangle
  use Bonfire.Common.Localise
  use Bonfire.Common.E
  alias Bonfire.Common.Utils
  alias Bonfire.PanDoRa.Auth
  use Bonfire.Common.Config
  use Bonfire.Common.Settings
  alias Bonfire.Common.Cache
  alias Bonfire.PanDoRa.Vault
  import Bonfire.PanDoRa

  # Cache TTL of 1 hour
  @cache_ttl :timer.hours(1)
  # Fixed filter types (legacy-style, deterministic, no init/site_config needed)
  @filter_types_fixed ~w(director featuring language country year keywords)
  # Kept for backward compat where @metadata_keys is referenced
  @metadata_keys @filter_types_fixed
  @metadata_fields @filter_types_fixed

  # Filter type (UI) <-> API key. Pandora schema uses "keyword" (singular) for the field.
  # UI uses "keywords" (plural); conditions and group must use "keyword" to match Pandora.
  @filter_type_to_api_key %{"keywords" => "keyword"}
  @api_key_to_filter_type %{"keyword" => "keywords"}
  # Pandora parseCondition uses "==" for facet fields (director, featuring, year, keyword).

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
  def find(opts) do
    conditions = Keyword.get(opts, :conditions, [])
    debug(opts, "Client.find called with opts")

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

    case make_request("find", items_payload, opts) |> debug("made_find_request") do
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
  def fetch_all_metadata(conditions \\ [], opts) do
    filter_keys = get_filter_keys(opts)
    cache_key = "pandora_metadata_#{get_pandora_url()}_#{:erlang.phash2(conditions)}"

    case Cache.get!(cache_key) do
      nil ->
        tasks =
          filter_keys
          |> Enum.map(fn field ->
            Task.async(fn ->
              fetch_field_metadata(field, conditions, nil, opts)
            end)
          end)

        results = Task.await_many(tasks, 30_000)

        metadata =
          results
          |> Enum.zip(filter_keys)
          |> Enum.reduce(%{}, fn {result, key}, acc ->
            Map.put(acc, "#{key}s", result)
          end)

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
    limit = Keyword.get(opts, :limit, 20)
    filter_keys = get_filter_keys(opts)

    tasks =
      filter_keys
      |> Enum.map(fn field ->
        Task.async(fn ->
          fetch_field_metadata(field, conditions, limit, opts)
        end)
      end)

    results = Task.await_many(tasks, 10_000)

    metadata =
      results
      |> Enum.zip(filter_keys)
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
  def fetch_grouped_metadata(conditions, opts) do
    debug("Starting grouped metadata fetch")

    page = Keyword.get(opts, :page, 0)
    per_page = Keyword.get(opts, :per_page, 10)
    field = Keyword.get(opts, :field)

    start_idx = page * per_page
    end_idx = start_idx + per_page - 1

    debug(
      "fetching grouped metadata for field #{field} with page #{page} and per_page #{per_page}"
    )

    # Prefer explicit `fields:` opt, then single `field:`, then fallback to get_filter_keys
    fields =
      cond do
        field -> [field]
        Keyword.has_key?(opts, :fields) -> Keyword.get(opts, :fields)
        true -> get_filter_keys(opts)
      end

    # Make a single request per field but in parallel.
    # For "keywords": try both "keyword" and "keywords" (instance-dependent).
    tasks =
      fields
      |> Enum.map(fn field ->
        Task.async(fn ->
          api_keys = api_keys_for_field(field)

          items =
            Enum.reduce_while(api_keys, [], fn api_key, acc ->
              payload = %{
                query: %{
                  conditions: conditions,
                  operator: "&"
                },
                group: api_key,
                sort: [%{key: "items", operator: "-"}],
                range: [start_idx, end_idx]
              }

              debug("Making request for field #{field} (api_key=#{api_key})")
              result = make_request("find", payload, opts)
              debug(result, "Got result for field #{field}")

              case result do
                {:ok, %{"items" => items}} when is_list(items) and items != [] ->
                  {:halt, items}

                _ ->
                  {:cont, acc}
              end
            end)

          {field, items}
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
  def fetch_grouped_field(field, conditions, opts) when is_binary(field) do
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

    case make_request("find", payload, opts) do
      {:ok, %{"items" => items}} when is_list(items) ->
        # API returns items in format [%{"name" => value, "items" => count}, ...]
        items

      _ ->
        []
    end
  end

  def get_movie(movie_id, opts) do
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
        "genere",
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
        "selezionato",
        "cutsperminute",
        "featuring"
      ]
    }

    case make_request("get", payload, opts) do
      {:ok, %{} = data} ->
        # IO.inspect(data, label: "Movie data retrieved")
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
  def get_list(id, opts) when is_binary(id) do
    case make_request("getList", %{id: id}, opts) do
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
  def init(opts) do
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
  def find_lists(opts) do
    opts = Utils.to_options(opts)

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
          [%{key: "user", operator: "==", value: opts[:user]}]

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

    case make_request("findLists", payload, opts) do
      {:ok, %{"items" => items}} when is_list(items) ->
        debug(items, "Received lists")
        {:ok, %{items: items, total: length(items)}}

      other ->
        error(other, l("Could not find any lists"))
    end
  end

  # Fetch public lists for current user
  def my_lists(opts) do
    find_lists(
      [
        keys: ["id", "description", "poster_frames", "posterFrames", "name", "status", "user"],
        sort: [%{key: "name", operator: "+"}],
        type: :user,
        # TODO: based on current creds?
        user:
          Settings.get([:bonfire_pandora, __MODULE__, :credentials], %{}, opts)[:username] ||
            get_auth_default_user()
      ] ++
        opts
    )
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
  def edit_list(id, params, opts) when is_map(params) or is_list(params) do
    # Convert params to map if they're keyword list
    params = if is_list(params), do: Map.new(params), else: params

    # Ensure we have an ID
    params = Map.put(params, "id", id)

    case make_request("editList", params, opts) do
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
  def remove_list(id, opts) do
    case make_request("removeList", %{id: id}, opts) do
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
  def add_list_items(list_id, opts) do
    cond do
      items = Keyword.get(opts, :items) ->
        payload = %{
          list: list_id,
          items: items
        }

        case make_request("addListItems", payload, opts) do
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
  def remove_list_items(list_id, opts) do
    cond do
      items = Keyword.get(opts, :items) ->
        payload = %{
          list: list_id,
          items: items
        }

        case make_request("removeListItems", payload, opts) do
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
  def add_list(params, opts) do
    # Convert params to map if they're keyword list
    params = if is_list(params), do: Map.new(params), else: params

    # Ensure name is present and properly formatted
    params =
      Map.update(params, "name", "Untitled", fn name ->
        name = if is_binary(name), do: String.trim(name), else: ""
        if name == "", do: "Untitled", else: name
      end)

    case make_request("addList", params, opts) do
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
  def find_list_items(list_id, opts) do
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

    case make_request("find", payload, opts) do
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
  def add_annotation(data, opts) when is_map(data) do
    # Validate required fields
    required_fields = [:item, :layer, :in, :out, :value]

    if Enum.all?(required_fields, &Map.has_key?(data, &1)) do
      make_request("addAnnotation", data, opts)
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
  def edit_annotation(data, opts) when is_map(data) do
    # Validate required fields
    if Map.has_key?(data, :id) do
      make_request("editAnnotation", data, opts)
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
  def remove_annotation(id, opts) when is_binary(id) do
    make_request("removeAnnotation", %{id: id}, opts)
  end

  @doc """
  Edits metadata of a movie item

  ## Parameters
    * `data` - Map containing:
      * `:id` - The item id (required)
      * Additional key/value pairs for the fields to update

  ## Examples
      iex> edit_movie(%{id: "movie123", title: "New Title", director: ["Alice"], summary: "...", year: "2023", featuring: ["Bob"], country: "Italy", language: "Italian"})
      {:ok, %{title: "New Title", year: "2023"}}
  """
  def edit_movie(data, opts) when is_map(data) do
    # Validate required fields
    if Map.has_key?(data, :id) do
      make_request("edit", data, opts)
    else
      {:error, "Missing required field: id"}
    end
  end

  # Formatta errori API Pandora (map) in messaggio leggibile per log e UI
  defp format_pandora_error(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join(", ")
    |> case do
      "" -> l("API data not recognised")
      msg -> "Pandora: " <> msg
    end
  end

  defp format_pandora_error(_), do: l("API data not recognised")

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
       when field_type in ~w(director sezione edizione featuring keywords) do
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
  defp fetch_field_metadata(field, conditions, limit \\ nil, opts) do
    api_key = filter_type_to_api_key(field)

    payload = %{
      query: %{
        conditions: conditions,
        # Default to AND operator
        operator: "&"
      },
      keys: [api_key],
      group_by: [
        %{
          key: api_key,
          sort: [%{key: "items", operator: "-"}],
          limit: limit || 1000
        }
      ]
    }

    debug(payload, "Making metadata request for #{field} (api_key=#{api_key})")

    case make_request("find", payload, opts) do
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
  def make_request(endpoint, payload, opts, retry_count \\ 0) do
    api_url = get_api_url()
    debug(payload, "Making request to #{endpoint} on #{api_url} with payload")

    opts =
      Utils.to_options(opts)
      |> debug("opts")

    username = opts[:username] || Auth.default_username()

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
      |> Auth.attach_request_auth(username, endpoint, opts)

    # |> debug("reqqq")

    case Req.post(req,
           form: %{
             action: endpoint,
             data: Jason.encode!(payload)
           }
         ) do
      {:ok, %Req.Response{status: 200, headers: headers, body: body}} ->
        # debug(body, "API Response (raw)")

        save_cookie = Auth.persist_session_cookie(headers, username, endpoint, opts)

        case maybe_return_data(body) do
          {:ok, data} ->
            extra =
              case save_cookie do
                {:ok, v} -> v
                _ -> %{}
              end

            {:ok, Map.merge(data, extra)}

          {:error, e} ->
            {:error, e}

          _ ->
            save_cookie || error(l("No data received from API"))
        end
        |> debug("API Response from #{endpoint}")

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

  defp maybe_return_data(%{"data" => %{"errors" => errors}}) do
    Logger.info("[PanDoRa API] error response: #{inspect(errors)}")
    error(errors, format_pandora_error(errors))
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

  # Pandora may return validation errors in data without "errors" or "status" key
  # (e.g. %{"data" => %{"email" => "E-mail address already exists"}})
  defp maybe_return_data(%{"data" => data}) when is_map(data) do
    if not Map.has_key?(data, "user") and
         (Map.has_key?(data, "email") or Map.has_key?(data, "username")) do
      Logger.info("[PanDoRa API] error response (data): #{inspect(data)}")
      error(data, format_pandora_error(data))
    else
      {:ok, data}
    end
  end

  defp maybe_return_data(%{} = data) do
    {:ok, data}
  end

  defp maybe_return_data(nil) do
    nil
  end

  defp maybe_return_data(body) do
    Logger.info("[PanDoRa API] unrecognised response: #{inspect(body)}")
    msg = if is_map(body), do: format_pandora_error(body), else: l("API data not recognised")
    error(body, msg)
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

  defp sign_up(user, email, username, password)
       when is_binary(email) and is_binary(username) and is_binary(password) do
    payload = %{
      email: email,
      username: username,
      password: password
    }

    with {:ok, %{"user" => %{} = pandora_user}} <-
           make_request("signup", payload, current_user: user, username: username) do
      if user,
        do: save_user_credentials(user, email, username, password),
        else: {:ok, pandora_user}
    end
  end

  defp sign_up(_user, email, username, password) do
    error(email, "Invalid details to sign up to Pandora")
  end

  def save_user_credentials(user, email, username, password) do
    case Vault.encrypt(password) do
      {:ok, encrypted_password} ->
        Settings.put(
          [:bonfire_pandora, __MODULE__, :credentials],
          %{
            email: email,
            username: username,
            password: Base.encode64(encrypted_password)
          },
          current_user: user
        )

      e ->
        error(
          e,
          "Could not encrypt your password to store it on the server, please save it in your own password vault: #{password}"
        )
    end
  end

  @doc """
  Syncs the current Bonfire user to Pandora using a signin-first flow.

  Behaviour:
  1. Save the provided password as the Pandora credential for this Bonfire user.
  2. Try signing in to Pandora with the Bonfire username/email identity.
  3. If the Pandora user does not exist yet, sign up on Pandora.
  4. Immediately sign in and persist the Pandora session cookie for runtime use.

  This is intended for the v1 manual recovery/bootstrap flow exposed by the
  Sync Pandora settings tool.
  """
  def sync_new_user_to_pandora(user, password)
      when is_binary(password) and password != "" do
    username = e(user, :character, :username, nil)
    account =
      repo().maybe_preload(e(user, :account, nil) || e(user, :accounted, :account, nil), :email)
    email = e(account, :email, :email_address, nil)

    if is_binary(username) and is_binary(email) do
      with {:ok, _} <- save_user_credentials(user, email, username, password) do
        case sign_in(username, password, current_user: user) do
          {:ok, _} = ok ->
            maybe_create_and_store_token(user)
            ok

          {:error, %{"username" => _}} ->
            create_and_sign_in_pandora_user(user, email, username, password)

          {:error, %{"email" => _}} ->
            create_and_sign_in_pandora_user(user, email, username, password)

          other ->
            other
        end
      end
    else
      error(
        user,
        l("Need a profile username and account email to connect to Pandora")
      )
    end
  end

  def sync_new_user_to_pandora(_user, _), do: error(:bad_password, l("Password is required"))

  defp create_and_sign_in_pandora_user(user, email, username, password) do
    case sign_up(user, email, username, password) do
      {:ok, _} ->
        sign_in_and_maybe_token(username, password, user)

      {:error, %{"email" => _}} ->
        sign_in_and_maybe_token(username, password, user)

      {:error, %{"username" => _}} ->
        sign_in_and_maybe_token(username, password, user)

      other ->
        other
    end
  end

  defp sign_in_and_maybe_token(username, password, user) do
    case sign_in(username, password, current_user: user) do
      {:ok, _} = ok ->
        maybe_create_and_store_token(user)
        ok

      other ->
        other
    end
  end

  defp maybe_create_and_store_token(user) do
    case create_pandora_token(current_user: user) do
      {:ok, token} ->
        Auth.put_pandora_token(user, token)
        :ok

      _ ->
        :ok
    end
  end

  def sign_up(opts \\ []) do
    user = Utils.current_user_required!(opts)
    username = e(user, :character, :username, nil)

    account =
      repo().maybe_preload(e(user, :account, nil) || e(user, :accounted, :account, nil), :email)

    email = e(account, :email, :email_address, nil)

    pw = :crypto.strong_rand_bytes(32) |> Base.encode64()

    with {:error, %{"username" => "Username already exists"}} <-
           sign_up(user, email, username, pw),
         username = "#{username}_bonfire",
         {:error, e} <- sign_up(user, email, username, pw) do
      Logger.info("[PanDoRa API] sign_up error: #{inspect(e)}")
      error(e, format_pandora_error(e))
    else
      # Email already exists on Pandora: try sign_in with saved credentials from the Sync Pandora tool.
      {:error, %{"email" => _} = err} ->
        case sign_in(opts) do
          {:ok, data} -> {:ok, data}
          _ ->
            error(
              err,
              l(
                "This email is already registered on Pandora. Use 'Sync Pandora' in Settings to sign in with your password."
              )
            )
        end

      other ->
        other
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
  def sign_in(username, password, opts \\ []) do
    Auth.clear_session(username, opts)

    payload = %{
      username: username,
      password: password
    }

    make_request("signin", payload, Utils.to_options(opts) ++ [username: username])
  end

  def sign_in(opts \\ []) do
    case Auth.credentials(opts) do
      {username, password} when is_binary(username) and is_binary(password) ->
        sign_in(username, password, opts)

      {:error, :no_credentials} ->
        if !opts[:looping] do
          with {:ok, %{__context__: context}} <- sign_up(opts) do
            sign_in(Enum.into(context, looping: true))
          else
            e ->
              error(e, l("Could not sign up on Pandora"))
          end
        else
          error(l("No Pandora credentials found for the current user"))
        end

      e ->
        error(e, l("No Pandora username/password found"))
    end
  end

  def get_session_cookie(username, opts) do
    Auth.session_cookie(username, opts)
  end

  def get_auth_default_user do
    Auth.default_username()
  end

  @doc """
  Calls the Pandora `init` action and returns the `site` object.
  The result is cached for `@cache_ttl`.
  The site object contains `itemKeys` (with filter/type info), `sortKeys`, etc.
  """
  @doc """
  Fetches the Pandora site config via the public `init` endpoint.
  Uses a direct HTTP call (no auth required) and caches the result for `@cache_ttl`.
  """
  def get_site_config(_opts \\ []) do
    cache_key = "pandora_site_config_#{get_pandora_url()}"

    case Cache.get!(cache_key) do
      nil ->
        result =
          try do
            req =
              Req.new(
                url: get_api_url(),
                connect_options: [timeout: 3_000],
                receive_timeout: 5_000
              )

            case Req.post(req, form: %{action: "init", data: "{}"}) do
              {:ok, %{status: 200, body: body}} ->
                decoded =
                  if is_binary(body), do: Jason.decode(body), else: {:ok, body}

                case decoded do
                  {:ok, %{"data" => %{"site" => site}}} when is_map(site) ->
                    {:ok, site}

                  {:ok, other} ->
                    warn(other, "[PanDoRa] init: unexpected response structure")
                    {:error, :unexpected_response}

                  {:error, reason} ->
                    warn(reason, "[PanDoRa] init: JSON decode error")
                    {:error, :json_error}
                end

              {:ok, %{status: status}} ->
                warn(status, "[PanDoRa] init: HTTP error #{status}")
                {:error, {:http_error, status}}

              {:error, reason} ->
                warn(reason, "[PanDoRa] init: request failed")
                {:error, reason}
            end
          rescue
            e ->
              warn(e, "[PanDoRa] init: exception in get_site_config")
              {:error, :exception}
          end

        case result do
          {:ok, site} ->
            Cache.put(cache_key, site, ttl: @cache_ttl)
            {:ok, site}

          err ->
            err
        end

      site ->
        {:ok, site}
    end
  end

  @doc """
  Returns the fixed list of filterable keys. Deterministic, no init/site_config call.
  Uses legacy-style hardcoded list: director, featuring, language, country, year, keywords.
  """
  def get_filter_keys(_opts \\ []) do
    @filter_types_fixed
  end

  @doc """
  Maps filter type (UI) to API key. Pandora uses "keyword" (singular), we use "keywords" (plural) in UI.
  """
  def filter_type_to_api_key(type) when is_binary(type) do
    Map.get(@filter_type_to_api_key, type, type)
  end

  # For "keywords": try both "keyword" and "keywords" (instance-dependent).
  defp api_keys_for_field("keywords"), do: ["keyword", "keywords"]
  defp api_keys_for_field(field), do: [filter_type_to_api_key(field)]

  @doc """
  Maps API key to filter type (UI). Use when receiving field from extra_metadata (e.g. "keyword" -> "keywords").
  """
  def api_key_to_filter_type(api_key) when is_binary(api_key) do
    Map.get(@api_key_to_filter_type, api_key, api_key)
  end

  @doc """
  Returns the comparison operator for a filter type.
  Pandora uses "==" for all facet fields (director, featuring, year, keyword).
  See item/managers.py parseCondition: facet_keys use get_operator(op, 'istr') → "==" = __iexact.
  """
  def operator_for_filter_type(_type), do: "=="

  @doc """
  Returns ALL item key ids for this Pandora instance (not just filterable ones).
  Falls back to a default list if the site config is not available.
  """
  def get_item_keys(opts \\ []) do
    case get_site_config(opts) do
      {:ok, %{"itemKeys" => item_keys}} when is_list(item_keys) ->
        Enum.map(item_keys, fn %{"id" => id} -> id end)

      _ ->
        ["title", "id", "director", "year", "duration", "summary"] ++ @metadata_keys
    end
  end

  def get_pandora_url do
    Bonfire.Common.Config.get!([:bonfire_pandora, :pandora_url])
  end

  defp get_api_url do
    get_pandora_url() <> "/api/"
  end

  @doc """
  Returns the Bonfire-internal proxy URL for a Pandora image/thumbnail.
  The proxy adds authentication server-side, so the browser can load it directly.
  Example: media_proxy_url("FZV", "icon128.jpg") → "/archive/media/FZV/icon128.jpg"
  """
  def media_proxy_url(item_id, filename) when is_binary(item_id) and is_binary(filename) do
    "/archive/media/#{item_id}/#{filename}"
  end

  @doc """
  Returns the best URL for a Pandora image/thumbnail: direct URL with ?token= when
  a token exists (faster loading), otherwise the proxy URL.
  """
  def media_url(item_id, filename, opts \\ []) when is_binary(item_id) and is_binary(filename) do
    opts = Utils.to_options(opts)

    case Auth.pandora_token(opts) do
      token when is_binary(token) and token != "" ->
        base = String.trim_trailing(get_pandora_url() || "", "/")
        "#{base}/#{item_id}/#{filename}?token=#{token}"

      _ ->
        media_proxy_url(item_id, filename)
    end
  end

  @doc """
  Returns the Bonfire-internal proxy URL for a Pandora video stream.
  Supports HTTP Range requests so the player can seek.
  Example: video_proxy_url("FZV", "480p.mp4") -> "/archive/video/FZV/480p.mp4"
  """
  def video_proxy_url(item_id, filename) when is_binary(item_id) and is_binary(filename) do
    "/archive/video/#{item_id}/#{filename}"
  end

  @doc """
  Returns the best URL for a Pandora video: direct URL with ?token= when a token
  exists (faster playback), otherwise the proxy URL.
  """
  def video_url(item_id, filename, opts \\ []) when is_binary(item_id) and is_binary(filename) do
    opts = Utils.to_options(opts)

    case Auth.pandora_token(opts) do
      token when is_binary(token) and token != "" ->
        base = String.trim_trailing(get_pandora_url() || "", "/")
        "#{base}/#{item_id}/#{filename}?token=#{token}"

      _ ->
        video_proxy_url(item_id, filename)
    end
  end

  @doc """
  Creates a Pandora access token via POST /api/tokens. Requires a valid session cookie.
  Returns {:ok, token_value} or {:error, reason}.
  """
  def create_pandora_token(opts \\ []) do
    opts = Utils.to_options(opts)

    case Auth.auth_headers(opts) do
      nil ->
        {:error, :no_session}

      headers when is_list(headers) ->
        url = String.trim_trailing(get_pandora_url() || "", "/") <> "/api/tokens"
        req_headers = [{"x-create-token", "1"} | headers]

        req =
          Req.new(
            url: url,
            headers: req_headers,
            connect_options: [timeout: 3_000],
            receive_timeout: 5_000
          )

        case Req.post(req, body: "") do
          {:ok, %Req.Response{status: 200, body: body}} ->
            decoded =
              case body do
                %{} = m -> {:ok, m}
                b when is_binary(b) -> Jason.decode(b)
                _ -> {:error, :invalid_body}
              end

            case decoded do
              {:ok, %{"data" => %{"value" => value}}} when is_binary(value) ->
                {:ok, value}

              {:ok, %{"data" => _}} ->
                {:error, :no_value_in_response}

              _ ->
                {:error, :invalid_response}
            end

          {:ok, %Req.Response{status: 403}} ->
            {:error, :forbidden}

          {:ok, %Req.Response{status: 401}} ->
            {:error, :unauthorized}

          {:ok, %Req.Response{status: status}} ->
            {:error, {:http_status, status}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Returns the best video filename for a given movie, based on the `stream` field.
  Falls back to 480p.mp4 if stream info is not available.
  """
  def best_video_filename(movie) when is_map(movie) do
    resolution = movie["stream"]
    format = "mp4"

    if is_integer(resolution) and resolution > 0 do
      "#{resolution}p.#{format}"
    else
      "480p.mp4"
    end
  end

  def best_video_filename(_), do: "480p.mp4"

  @doc """
  Basic test function for annotations following API structure
  """
  def fetch_annotations(movie_id, opts) do
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

    case make_request("findAnnotations", data, opts) do
      {:ok, %{"items" => items}} when is_list(items) ->
        debug(items, "Annotations fetched")
        {:ok, items}

      error ->
        debug(error, "Error fetching annotations")
        error
    end
  end
end
