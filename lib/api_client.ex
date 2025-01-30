defmodule PanDoRa.API.Client do
  @moduledoc """
  Optimized API client implementation for fetching and caching metadata
  """

  import Untangle
  use Bonfire.Common.Localise
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

    # Get total count first if needed
    total =
      if Keyword.get(opts, :total, false) do
        case make_request("find", %{
               query: %{
                 conditions: conditions,
                 operator: "&"
               },
               total: true
             }) do
          # Direct total
          {:ok, %{"data" => %{"items" => total}}} when is_integer(total) -> total
          # List of items
          {:ok, %{"data" => %{"items" => items}}} when is_list(items) -> length(items)
          _ -> 0
        end
      else
        # Don't fetch total if not needed
        nil
      end

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
      {:ok, %{"data" => %{"items" => items}}} when is_list(items) ->
        {:ok,
         %{
           items: items,
           total: total || length(items),
           has_more: total && length(items) < total
         }}

      error ->
        error
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
  def fetch_metadata(conditions, opts \\ []) do
    # High limit to get comprehensive data
    limit = Keyword.get(opts, :limit, 5000)

    tasks =
      @metadata_keys
      |> Enum.map(fn field ->
        Task.async(fn ->
          fetch_field_metadata(field, conditions, limit)
        end)
      end)

    results = Task.await_many(tasks, 30_000)

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
  Fetches grouped metadata for filters using the API's group parameter.
  """
  def fetch_grouped_metadata(conditions \\ []) do
    debug("Fetching grouped metadata with conditions: #{inspect(conditions)}")

    tasks =
      @metadata_fields
      |> Enum.map(fn field ->
        Task.async(fn ->
          {field, fetch_grouped_field(field, conditions)}
        end)
      end)

    results = Task.await_many(tasks, :timer.seconds(10))
    metadata = Map.new(results)
    debug("Grouped metadata results: #{inspect(metadata)}")
    # Return with :ok tuple
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
        operator: "&"
      },
      # Group results by the specified field
      group: field,
      # Sort by number of items descending
      sort: [%{key: "items", operator: "-"}],
      # Get up to 1000 grouped results
      range: [0, 1000]
    }

    case make_request("find", payload) do
      {:ok, %{"data" => %{"items" => items}}} when is_list(items) ->
        # API returns items in format [%{"name" => value, "items" => count}, ...]
        items

      {:ok, response} ->
        case get_in(response, ["data", "items"]) do
          items when is_list(items) -> items
          _ -> []
        end

      _ ->
        []
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

    debug("Making metadata request for #{field} with payload: #{inspect(payload)}")

    case make_request("find", payload) do
      {:ok, %{"data" => %{"items" => items}}} when is_list(items) ->
        items
        |> Enum.map(fn item ->
          %{"name" => Map.get(item, "name", ""), "items" => Map.get(item, "items", 0)}
        end)

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
  def make_request(endpoint, payload) do
    debug("Making request to #{endpoint} with payload: #{inspect(payload)}")
    api_url = get_api_url()

    req =
      Req.new(
        url: api_url,
        connect_options: [timeout: 5_000],
        receive_timeout: 15_000
      )

    form_data = %{
      action: endpoint,
      data: Jason.encode!(payload)
    }

    case Req.post(req, form: form_data) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, decoded} ->
            debug(decoded, label: "API Response")
            {:ok, decoded}

          {:error, reason} ->
            debug("JSON decode error: #{inspect(reason)}")
            {:error, "Invalid JSON response"}
        end

      {:ok, %Req.Response{status: 200, body: body}} ->
        debug(body, label: "API Response (raw)")
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        error(l("API request failed with status %{status}", status: status))
        {:error, "API request failed with status #{status}"}

      {:error, error} ->
        error(error, l("API request failed"))
        {:error, error}
    end
  end

  defp get_api_url do
    Bonfire.Common.Config.get([__MODULE__, :api_url], "https://0xdb.org/api/")
  end
end
