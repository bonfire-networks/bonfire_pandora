defmodule Bonfire.PanDoRa.Web.SearchLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias PanDoRa.API.Client

  @behaviour Bonfire.UI.Common.LiveHandler

  # Keep your existing extension declarations
  declare_extension("Federated Archives",
    icon: "mingcute:microscope-fill",
    emoji: "🔬",
    description: "Federated archives alliance",
    default_nav: [__MODULE__]
  )

  declare_nav_link("Search archive",
    page: "home",
    href: "/pandora",
    icon: "carbon:document"
  )

  # Add constants for better maintainability
  @filter_types ~w(director country year language)
  @default_per_page 20
  @default_keys ~w(title director country year language duration)

  # Clean initial assigns with defaults
  @initial_assigns %{
    page: 0,
    has_more_items: true,
    term: nil,
    loading: false,
    current_count: 0,
    total_count: 0,
    without_secondary_widgets: true,
    page_title: "Search in your archive",
    per_page: @default_per_page,
    available_directors: [],
    available_countries: [],
    available_years: [],
    available_languages: [],
    selected_directors: [],
    selected_countries: [],
    selected_years: [],
    selected_languages: [],
    error: nil
  }

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    debug("Mounting SearchLive")

    socket =
      socket
      |> stream_configure(:search_results,
        dom_id: &"result-#{&1["id"] || generate_stable_id(&1)}"
      )
      |> stream(:search_results, [])
      |> assign(@initial_assigns)
      |> assign(:nav_items, Bonfire.Common.ExtensionModule.default_nav())

    if connected?(socket) do
      {:ok, fetch_initial_data(socket)}
    else
      {:ok, socket}
    end
  end

  # Keep your existing handle_params implementation
  def handle_params(%{"term" => term}, _, socket) do
    if connected?(socket) do
      do_search(socket, term)
    else
      {:noreply, assign(socket, term: term)}
    end
  end

  def handle_params(_, _, socket), do: {:noreply, socket}

  # Unified filter handling using pattern matching
  def handle_event("filter_by_" <> filter_type, params, socket)
      when filter_type in @filter_types do
    debug("Filter params: #{inspect(params)}")

    socket =
      socket
      |> toggle_filter(filter_type, params[filter_type])
      |> reset_pagination()

    # Build conditions with the updated filters
    conditions =
      build_search_conditions(%{
        term: socket.assigns.term,
        selected_directors: socket.assigns.selected_directors,
        selected_countries: socket.assigns.selected_countries,
        selected_years: socket.assigns.selected_years,
        selected_languages: socket.assigns.selected_languages
      })

    # Update metadata with current conditions
    socket = update_metadata_with_conditions(socket, conditions)

    trigger_search(socket)
  end

  # New function to update metadata with current conditions
  defp update_metadata_with_conditions(socket, conditions) do
    case Client.fetch_grouped_metadata(conditions) do
      {:ok, metadata} ->
        socket
        |> assign(
          available_directors: metadata["director"] || [],
          available_countries: metadata["country"] || [],
          available_years: metadata["year"] || [],
          available_languages: metadata["language"] || []
        )

      _ ->
        socket
    end
  end

  # Update the existing update_metadata_for_term to use the new function
  defp update_metadata_for_term(socket, term) do
    conditions = [%{key: "title", operator: "~=", value: term}]
    update_metadata_with_conditions(socket, conditions)
  end

  # def handle_event("search", %{"term" => term}, socket) do
  #   do_search(socket, term)
  # end

  def handle_event("clear_search", _, socket) do
    {:noreply,
     socket
     |> assign(@initial_assigns)
     |> stream(:search_results, [], reset: true)
     # Add initial results after clear
     |> maybe_fetch_initial_results()}
  end

  # And make handle_event consistent:
  def handle_event("search", %{"term" => term}, socket) do
    socket =
      socket
      |> assign(
        selected_directors: [],
        selected_countries: [],
        selected_years: [],
        selected_languages: [],
        term: term
      )
      |> reset_pagination()
      |> set_loading_state(true)
      |> trigger_search()

    {:noreply, socket}
  end

  def handle_event("clear_filters", _, socket) do
    socket =
      socket
      |> assign(
        term: nil,
        selected_directors: [],
        selected_countries: [],
        selected_years: [],
        selected_languages: []
      )
      |> reset_pagination()
      |> set_loading_state(true)
      |> trigger_search()

    {:noreply, socket}
  end

  def handle_event("load_more", _, socket) do
    if socket.assigns.has_more_items do
      {:noreply,
       socket
       |> set_loading_state(true)
       |> do_load_more()}
    else
      {:noreply, socket}
    end
  end

  # Add back the handle_info implementation for metadata
  def handle_info({:fetch_initial_metadata, _conditions}, socket) do
    case Client.fetch_grouped_metadata() do
      {:ok, metadata} ->
        {:noreply,
         socket
         |> assign_metadata(metadata)
         |> set_loading_state(false)}

      _ ->
        {:noreply, socket}
    end
  end

  # Private functions for better state management
  def error_message(%{assigns: %{error: nil}}), do: nil
  def error_message(%{assigns: %{error: error}}), do: "Error: #{error}"

  defp maybe_fetch_metadata(%{assigns: assigns} = socket) do
    if connected?(socket) do
      case Client.fetch_grouped_metadata() do
        {:ok, metadata} ->
          socket
          |> assign_metadata(metadata)
          # Add this function
          |> maybe_fetch_initial_results()

        _ ->
          socket
      end
    else
      socket
    end
  end

  # defp maybe_fetch_initial_results(socket) do
  #   case Client.find(
  #     sort: [%{key: "title", operator: "+"}],
  #     page: 0,
  #     per_page: @default_per_page,
  #     keys: @default_keys
  #   ) do
  #     {:ok, %{items: items, total: total}} ->
  #       handle_search_success(socket, items, total)
  #     _ -> socket
  #   end
  # end

  defp fetch_initial_data(socket) do
    # Set loading at start
    socket = set_loading_state(socket, true)

    case Client.fetch_grouped_metadata() do
      {:ok, metadata} ->
        # Debug to verify metadata format
        debug("Received metadata: #{inspect(metadata)}")

        socket =
          socket
          |> assign_metadata(metadata)

        # Now fetch initial results
        case Client.find(
               sort: [%{key: "title", operator: "+"}],
               range: [0, @default_per_page],
               keys: @default_keys,
               total: true
             ) do
          {:ok, %{items: items, total: total}} ->
            {:noreply, updated_socket} = handle_search_success(socket, items, total)
            updated_socket

          _ ->
            socket |> set_loading_state(false)
        end

      # Handle case where metadata is returned directly without :ok tuple
      metadata when is_map(metadata) ->
        socket
        |> assign_metadata(metadata)
        |> set_loading_state(false)

      _ ->
        socket |> set_loading_state(false)
    end
  end

  defp maybe_fetch_initial_results(socket) do
    case Client.find(
           sort: [%{key: "title", operator: "+"}],
           page: 0,
           per_page: @default_per_page,
           keys: @default_keys
         ) do
      {:ok, %{items: items, total: total}} ->
        {:noreply, updated_socket} = handle_search_success(socket, items, total)
        updated_socket

      _ ->
        socket
    end
  end

  defp toggle_filter(socket, "country", value) do
    current_filters = Map.get(socket.assigns, :selected_countries, [])

    updated_filters =
      if value in current_filters do
        List.delete(current_filters, value)
      else
        [value | current_filters]
      end

    socket
    |> assign(:selected_countries, updated_filters)
    |> reset_pagination()
    |> trigger_search()
  end

  defp toggle_filter(socket, filter_type, value) do
    filter_key = String.to_existing_atom("selected_#{filter_type}s")
    current_filters = Map.get(socket.assigns, filter_key, [])

    updated_filters =
      if value in current_filters do
        List.delete(current_filters, value)
      else
        [value | current_filters]
      end

    socket
    |> assign(filter_key, updated_filters)
    |> reset_pagination()
    |> trigger_search()
  end

  defp reset_pagination(socket) do
    socket
    |> assign(page: 0)
    |> stream(:search_results, [], reset: true)
  end

  def set_loading_state(socket, loading) do
    assign(socket, loading: loading)
  end

  defp trigger_search(socket) do
    socket = set_loading_state(socket, true)
    {:noreply, updated_socket} = do_search(socket, socket.assigns.term)
    updated_socket
  end

  defp build_search_conditions(%{
         term: term,
         selected_directors: directors,
         selected_countries: countries,
         selected_years: years,
         selected_languages: languages
       }) do
    filters =
      []
      |> add_filter_condition("director", directors)
      |> add_filter_condition("country", countries)
      |> add_filter_condition("year", years)
      |> add_filter_condition("language", languages)

    case {term, filters} do
      {nil, []} ->
        []

      {term, []} when is_binary(term) and term != "" ->
        [%{key: "*", operator: "=", value: term}]

      {nil, filters} ->
        [%{conditions: filters, operator: "&"}]

      {term, filters} ->
        [
          %{
            conditions: [%{key: "*", operator: "=", value: term} | filters],
            operator: "&"
          }
        ]
    end
  end

  defp add_filter_condition(conditions, _type, []), do: conditions

  defp add_filter_condition(conditions, type, [value]),
    do: [%{key: type, operator: "==", value: value} | conditions]

  defp add_filter_condition(conditions, type, values) when length(values) > 0,
    do: [
      %{
        conditions: Enum.map(values, &%{key: type, operator: "==", value: &1}),
        operator: "|"
      }
      | conditions
    ]

  # Keep your existing implementations but update state management
  defp do_search(socket, term) do
    conditions =
      build_search_conditions(%{
        term: term,
        selected_directors: socket.assigns.selected_directors,
        selected_countries: socket.assigns.selected_countries,
        selected_years: socket.assigns.selected_years,
        selected_languages: socket.assigns.selected_languages
      })

    # Always update metadata regardless of term
    socket =
      case Client.fetch_grouped_metadata() do
        {:ok, metadata} ->
          socket
          |> assign_metadata(metadata)

        # |> assign(loading: true)  # Explicitly preserve loading state
        _ ->
          socket
          # |> assign(loading: true)  # Ensure loading state is preserved
      end

    case Client.find(
           conditions: conditions,
           range: [0, @default_per_page],
           keys: @default_keys,
           total: true
         ) do
      {:ok, %{items: items, total: total}} ->
        handle_search_success(socket, items, total)

      _ ->
        {:noreply, socket |> set_loading_state(false)}
    end
  end

  # New function to handle metadata updates
  defp update_metadata_for_term(socket, term) do
    conditions = [%{key: "title", operator: "~=", value: term}]
    update_metadata_with_conditions(socket, conditions)
  end

  defp sort_years(years) do
    Enum.sort_by(years, fn %{"name" => year} ->
      case Integer.parse(year) do
        # Negative to sort in descending order
        {num, _} -> -num
        _ -> 0
      end
    end)
  end

  defp assign_metadata(socket, metadata) do
    socket
    |> assign(
      available_directors: metadata["director"] || [],
      available_countries: metadata["country"] || [],
      available_years: sort_years(metadata["year"] || []),
      available_languages: metadata["language"] || []
    )
  end

  # Always update metadata regardless of term
  defp handle_search_success(socket, items, total) do
    current_count = length(items)
    total_pages = ceil(total / @default_per_page)

    socket =
      socket
      |> stream(:search_results, prepare_items(items))
      |> assign(
        current_count: current_count,
        total_count: total,
        page: 0,
        total_pages: total_pages,
        # Show load more if we have exactly per_page items (meaning there might be more)
        has_more_items: current_count == @default_per_page
      )

    # Only pass search conditions to metadata if there's a search term
    conditions =
      if socket.assigns.term && socket.assigns.term != "",
        do: build_search_conditions(socket.assigns),
        else: []

    # Update metadata with current search conditions
    case Client.fetch_grouped_metadata(conditions) do
      {:ok, metadata} ->
        {:noreply,
         socket
         |> assign(
           available_directors: metadata["director"] || [],
           available_countries: metadata["country"] || [],
           available_years: sort_years(metadata["year"] || []),
           available_languages: metadata["language"] || []
         )
         # Only set to false after everything is done
         |> set_loading_state(false)}

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_search_error(socket, error) do
    debug("Search error: #{inspect(error)}")

    {:noreply,
     socket
     |> assign(
       error: error,
       loading: false,
       current_count: 0,
       total_count: 0,
       has_more_items: false
     )}
  end

  defp do_load_more(socket) do
    next_page = socket.assigns.page + 1

    case Client.find(
           conditions: build_search_conditions(socket.assigns),
           range: calculate_page_range(next_page),
           keys: @default_keys,
           total: true
         ) do
      {:ok, %{items: items, total: total}} ->
        socket
        |> stream(:search_results, prepare_items(items))
        |> assign(
          page: next_page,
          current_count: socket.assigns.current_count + length(items),
          total_count: total,
          # Show load more only if we got exactly per_page items
          has_more_items: length(items) == @default_per_page,
          loading: false
        )

      {:error, error} ->
        handle_search_error(socket, error)
    end
  end

  defp calculate_page_range(page) do
    start_index = page * @default_per_page
    [start_index, start_index + @default_per_page]
  end

  defp handle_load_more_success(socket, %{items: items, total: total}, next_page) do
    new_count = socket.assigns.current_count + length(items)

    socket
    |> stream(:search_results, prepare_items(items))
    |> assign(
      page: next_page,
      current_count: new_count,
      total_count: total,
      has_more_items: new_count < total,
      loading: false
    )
  end

  defp handle_load_more_error(socket, error) do
    socket
    |> assign(error: error, loading: false)
  end

  # def do_load_more(socket) do
  #   conditions = build_search_conditions(socket.assigns)
  #   next_page = socket.assigns.page + 1
  #   per_page = 20
  #   start_index = next_page * per_page
  #   end_index = start_index + per_page - 1

  #   case Client.find(
  #     conditions: conditions,
  #     keys: ["title", "director", "country", "year", "language", "duration"],
  #     range: [start_index, end_index],
  #     total: true
  #   ) do
  #     {:ok, %{items: items, total: total}} ->
  #       new_count = socket.assigns.current_count + length(items)

  #       debug("""
  #       Load more results:
  #       - New items: #{length(items)}
  #       - New total count: #{new_count}
  #       - API total: #{total}
  #       - Has more: #{new_count < total}
  #       """)

  #       socket
  #       |> stream(:search_results, prepare_items(items))
  #       |> assign(
  #         page: next_page,
  #         current_count: new_count,
  #         total_count: total,
  #         has_more_items: new_count < total,
  #         loading: false
  #       )

  #     {:error, error} ->
  #       debug("Load more error: #{inspect(error)}")
  #       socket
  #       |> assign(
  #         error: error,
  #         loading: false
  #       )
  #   end
  # end

  # defp handle_search_results(socket, items, total, page) do
  #   socket
  #   |> stream(:search_results, prepare_items(items))
  #   |> assign(:total_count, total)
  #   |> assign(:page, page)
  # end

  defp prepare_items(items) do
    items
    |> Enum.map(fn item ->
      Map.put(item, "id", generate_stable_id(item))
    end)
  end

  defp generate_stable_id(item) do
    [
      Map.get(item, "title", ""),
      Map.get(item, "director", []) |> Enum.join("-"),
      Map.get(item, "year", "")
    ]
    |> Enum.join("-")
    |> :erlang.phash2()
    |> to_string()
  end

  def format_duration(duration) when is_binary(duration) do
    case Float.parse(duration) do
      {seconds, _} -> format_duration(seconds)
      :error -> duration
    end
  end

  def format_duration(seconds) when is_float(seconds) do
    total_minutes = trunc(seconds / 60)
    hours = div(total_minutes, 60)
    minutes = rem(total_minutes, 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}min"
      minutes > 0 -> "#{minutes}min"
      true -> "< 1min"
    end
  end
end
