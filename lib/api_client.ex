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
           total: length(items),
           has_more: false
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
    start_time = System.monotonic_time(:millisecond)
    # High limit to get comprehensive data
    limit = Keyword.get(opts, :limit, 20)

    tasks =
      @metadata_keys
      |> Enum.map(fn field ->
        Task.async(fn ->
          task_start = System.monotonic_time(:millisecond)
          result = fetch_field_metadata(field, conditions, limit)
          task_end = System.monotonic_time(:millisecond)
          debug("Metadata fetch for #{field} took #{task_end - task_start}ms")
          result
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

    end_time = System.monotonic_time(:millisecond)
    debug("Total metadata fetch took #{end_time - start_time}ms")
    {:ok, metadata}
  end

  @doc """
  Fetches grouped metadata for filters using the find endpoint with group parameter.
  """
  def fetch_grouped_metadata(conditions \\ []) do
    start_time = System.monotonic_time(:millisecond)
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
          debug("Got result for field #{field}: #{inspect(result)}")

          case result do
            {:ok, %{"data" => %{"items" => items}}} when is_list(items) ->
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

    end_time = System.monotonic_time(:millisecond)
    debug("Total metadata fetch took #{end_time - start_time}ms")
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
  def make_request(endpoint, payload, retry_count \\ 0) do
    start_time = System.monotonic_time(:millisecond)
    debug("Making request to #{endpoint} with payload: #{inspect(payload)}")
    api_url = get_api_url()

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

    form_data = %{
      action: endpoint,
      data: Jason.encode!(payload)
    }

    result =
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
          # Only retry once more on timeout
          if retry_count < 1 and match?(%Req.TransportError{reason: :timeout}, error) do
            debug("Retrying request after timeout")
            make_request(endpoint, payload, retry_count + 1)
          else
            {:error, error}
          end
      end

    end_time = System.monotonic_time(:millisecond)
    debug("Request to #{endpoint} took #{end_time - start_time}ms")
    result
  end

  defp get_api_url do
    Bonfire.Common.Config.get([__MODULE__, :api_url], "https://0xdb.org/api/")
  end
end
