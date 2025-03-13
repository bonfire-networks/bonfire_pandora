defmodule Bonfire.PanDoRa.Web.SearchLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Utils
  @behaviour Bonfire.UI.Common.LiveHandler

  # Add constants for better maintainability
  @filter_types ~w(director sezione edizione featuring)
  @default_per_page 20
  @filter_per_page 10
  @default_keys ~w(title id item_id public_id director sezione edizione featuring duration)
  @loading_states [:initial_load, :metadata_load, :search_load, :more_load]

  # Add component props
  prop term, :string
  prop current_user, :any

  # Clean initial assigns with defaults
  @initial_assigns %{
    page: 0,
    term: nil,
    loading: false,
    has_more_items: true,
    per_page: @default_per_page,

    # Filters list (to be abstracted)
    available_director: [],
    available_sezione: [],
    available_edizione: [],
    available_featuring: [],

    # Selected filters (to be abstracted)
    selected_director: [],
    selected_sezione: [],
    selected_edizione: [],
    selected_featuring: [],

    # Filter pagination state
    director_page: 0,
    sezione_page: 0,
    edizione_page: 0,
    featuring_page: 0,

    # Filter loading state
    director_loading: false,
    sezione_loading: false,
    edizione_loading: false,
    featuring_loading: false,

    # Filter more items flags
    has_more_director: true,
    has_more_sezione: true,
    has_more_edizione: true,
    has_more_featuring: true,
    first_selected_filter: nil,
    is_keyword_search: false,
    keep_keyword_filtering: false,
    error: nil,
    # Add this to track current filter state
    current_filters: %{}
  }

  # on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  # def mount(_params, _session, socket) do
  #   debug("Mounting SearchLive")

  #   socket =
  #     socket
  #     |> stream_configure(:search_results,
  #       dom_id: &"result-#{&1["stable_id"] || Utils.generate_stable_id(&1)}"
  #     )
  #     |> stream(:search_results, [])
  #     |> assign(@initial_assigns)
  #     |> assign(:page_title, "Search in your archive")
  #     |> assign(:without_secondary_widgets, true)
  #     |> assign(:nav_items, Bonfire.Common.ExtensionModule.default_nav())
  #     |> assign(:loading_states, MapSet.new())
  #     |> track_loading(:initial_load, true)

  #   # |> debug_loading_states("mount")

  #   if connected?(socket) do
  #     send(self(), :load_initial_data)
  #     {:ok, socket, temporary_assigns: [search_results: []]}
  #   else
  #     {:ok, socket}
  #   end
  # end

  def mount(socket) do
    socket =
      socket
      |> stream_configure(:search_results,
        dom_id: &"result-#{&1["stable_id"] || Utils.generate_stable_id(&1)}"
      )
      |> stream(:search_results, [])
      |> assign(@initial_assigns)
      |> assign(:loading_states, MapSet.new())
      |> track_loading(:initial_load, true)

    {:ok, socket}
  end

  def update(assigns, socket) do
    debug("Updating SearchComponent")

    socket =
      socket
      # Apply incoming assigns last
      |> assign(assigns)

    # if connected?(socket) do
    socket =
      if not is_nil(assigns[:term]) and assigns.term != "" do
        # If we have a term, perform a search
        do_initial_search(socket, assigns.term)
      else
        # Otherwise load the initial data
        fetch_initial_data(socket)
      end

    {:ok, socket}
  end

  # Add this helper function for the initial search
  defp do_initial_search(socket, term) do
    socket = track_loading(socket, :search_load, true)

    conditions =
      build_search_conditions(%{
        term: term,
        selected_director: socket.assigns.selected_director,
        selected_sezione: socket.assigns.selected_sezione,
        selected_edizione: socket.assigns.selected_edizione,
        selected_featuring: socket.assigns.selected_featuring
      })

    case Client.find(
           conditions: conditions,
           range: [0, @default_per_page],
           keys: @default_keys,
           total: true
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        socket =
          socket
          |> stream(:search_results, prepare_items(items_to_show), reset: true)
          |> assign(
            has_more_items: has_more,
            current_count: length(items_to_show),
            page: 0
          )
          |> track_loading(:search_load, false)

        # Handle metadata fetch separately
        case fetch_metadata(socket, conditions) do
          {:ok, updated_socket} ->
            updated_socket

          {:error, error_socket} ->
            error_socket
            |> put_flash(:error, l("Error updating filters"))
        end

      other ->
        error(other, "Search failed")

        socket
        |> assign_error(l("Search failed"))
        |> track_loading(:search_load, false)
    end
  end

  # def handle_info(:load_initial_data, socket) do
  #   socket = track_loading(socket, :initial_load, true)
  #   socket = fetch_initial_data(socket)

  #   {:noreply, socket}
  # end

  # def handle_info({:load_component_initial_data, id}, socket) when socket.id == id do
  #   IO.inspect("Loading initial data for component #{id}")
  #   socket = fetch_initial_data(socket)
  #   {:noreply, socket}
  # end

  def do_component_search(socket, term) do
    socket = track_loading(socket, :search_load, true)

    conditions =
      build_search_conditions(%{
        term: term,
        selected_director: socket.assigns.selected_director,
        selected_sezione: socket.assigns.selected_sezione,
        selected_edizione: socket.assigns.selected_edizione,
        selected_featuring: socket.assigns.selected_featuring
      })

    case Client.find(
           conditions: conditions,
           range: [0, @default_per_page],
           keys: @default_keys,
           total: true
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        socket =
          socket
          |> stream(:search_results, prepare_items(items_to_show), reset: true)
          |> assign(
            has_more_items: has_more,
            current_count: length(items_to_show),
            page: 0
          )
          |> track_loading(:search_load, false)

        # Handle metadata fetch separately
        case fetch_metadata(socket, conditions) do
          {:ok, updated_socket} ->
            {:noreply, updated_socket}

          {:error, error_socket} ->
            {:noreply,
             error_socket
             |> put_flash(:error, l("Error updating filters"))}
        end

      other ->
        error(other, "Search failed")

        {:noreply,
         socket
         |> assign_error(l("Search failed"))
         |> track_loading(:search_load, false)}
    end
  end

  # def handle_info({:do_component_search, id, term}, socket) when socket.id == id do
  #   IO.inspect("Searching for #{term} in component #{id}")
  #   socket = track_loading(socket, :search_load, true)

  #   conditions =
  #     build_search_conditions(%{
  #       term: term,
  #       selected_director: socket.assigns.selected_director,
  #       selected_sezione: socket.assigns.selected_sezione,
  #       selected_edizione: socket.assigns.selected_edizione,
  #       selected_featuring: socket.assigns.selected_featuring
  #     })

  #   case Client.find(
  #          conditions: conditions,
  #          range: [0, @default_per_page],
  #          keys: @default_keys,
  #          total: true
  #        ) do
  #     {:ok, %{items: items}} when is_list(items) ->
  #       {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

  #       socket =
  #         socket
  #         |> stream(:search_results, prepare_items(items_to_show), reset: true)
  #         |> assign(
  #           has_more_items: has_more,
  #           current_count: length(items_to_show),
  #           page: 0
  #         )
  #         |> track_loading(:search_load, false)

  #       # Handle metadata fetch separately
  #       case fetch_metadata(socket, conditions) do
  #         {:ok, updated_socket} ->
  #           {:noreply, updated_socket}

  #         {:error, error_socket} ->
  #           {:noreply,
  #            error_socket
  #            |> put_flash(:error, l("Error updating filters"))}
  #       end

  #     other ->
  #       error(other, "Search failed")

  #       {:noreply,
  #        socket
  #        |> assign_error(l("Search failed"))
  #        |> track_loading(:search_load, false)}
  #   end
  # end

  # Keep these handlers for search operations triggered by events
  def handle_info({:do_component_search, id, term}, socket) when socket.id == id do
    debug("Searching for #{term} in component #{id}")
    socket = do_initial_search(socket, term)
    {:noreply, socket}
  end

  def handle_info({:do_search, term}, socket) do
    socket = do_initial_search(socket, term)
    {:noreply, socket}
  end

  def handle_info({_ref, {filter_type, data}}, socket) when filter_type in @filter_types do
    # Update the corresponding filter data in assigns
    assign_key =
      case filter_type do
        "director" -> :available_director
        "sezione" -> :available_sezione
        "edizione" -> :available_edizione
        "featuring" -> :available_featuring
      end

    {:noreply, assign(socket, assign_key, data)}
  end

  # Add back the handle_info implementation for metadata
  def handle_info({:fetch_initial_metadata, conditions}, socket) do
    socket = track_loading(socket, :global_load, true)

    case Client.fetch_grouped_metadata(conditions, per_page: @filter_per_page) do
      {:ok, metadata} ->
        socket =
          socket
          |> assign(:available_director, Map.get(metadata, "director", []))
          |> assign(:available_sezione, Map.get(metadata, "sezione", []))
          |> assign(:available_edizione, Map.get(metadata, "edizione", []))
          |> assign(:available_featuring, Map.get(metadata, "featuring", []))
          |> assign(:director_page, 0)
          |> assign(:sezione_page, 0)
          |> assign(:edizione_page, 0)
          |> assign(:featuring_page, 0)
          |> assign(
            :has_more_director,
            length(Map.get(metadata, "director", [])) >= @filter_per_page
          )
          |> assign(
            :has_more_sezione,
            length(Map.get(metadata, "sezione", [])) >= @filter_per_page
          )
          |> assign(
            :has_more_edizione,
            length(Map.get(metadata, "edizione", [])) >= @filter_per_page
          )
          |> assign(
            :has_more_featuring,
            length(Map.get(metadata, "featuring", [])) >= @filter_per_page
          )
          |> track_loading(:global_load, false)

        {:noreply, socket}

      {:error, _} ->
        socket =
          socket
          |> put_flash(:error, l("Error fetching metadata"))
          |> track_loading(:global_load, false)

        {:noreply, socket}
    end
  end

  def handle_info({:set_loading_state, state}, socket) do
    {:noreply, track_loading(socket, :global_load, state)}
  end

  def handle_info({:do_search, term}, socket) do
    send(self(), {:do_component_search, socket.id, term})
    {:noreply, socket}
  end

  # Handle the DOWN message that follows
  def handle_info({:DOWN, _ref, :process, _pid, :normal}, socket) do
    {:noreply, socket}
  end

  # Catch-all clause for unexpected messages
  def handle_info(msg, socket) do
    debug("SearchComponent received unexpected message: #{inspect(msg)}")
    {:noreply, socket}
  end

  # Unified filter handling using pattern matching
  def handle_event("filter_by_" <> filter_type, params, socket)
      when filter_type in @filter_types do
    debug("Filter params: #{inspect(params)}")
    debug("Current filters before update: #{inspect(socket.assigns.current_filters)}")

    socket =
      socket
      |> toggle_filter(filter_type, params["id"])

    {:noreply, socket}
  end

  # Add handlers for infinite scroll
  def handle_event("load_more_" <> filter_type, _params, socket)
      when filter_type in @filter_types do
    # Map the filter type to the correct assign key
    assign_key =
      case filter_type do
        "director" -> :available_director
        "sezione" -> :available_sezione
        "edizione" -> :available_edizione
        "featuring" -> :available_featuring
      end

    page_key = String.to_atom("#{filter_type}_page")
    loading_key = String.to_atom("#{filter_type}_loading")
    has_more_key = String.to_atom("has_more_#{filter_type}")

    current_page = Map.get(socket.assigns, page_key, 0)
    conditions = build_search_conditions(socket.assigns)

    socket = assign(socket, loading_key, true)
    socket = track_loading(socket, String.to_atom("#{filter_type}_load"), true)

    case Client.fetch_grouped_metadata(conditions,
           field: filter_type,
           page: current_page + 1,
           per_page: @filter_per_page
         ) do
      {:ok, metadata} ->
        items = Map.get(metadata, filter_type, [])
        current_items = Map.get(socket.assigns, assign_key, [])

        new_items =
          Enum.filter(items, fn %{"name" => name} ->
            not Enum.any?(current_items, fn %{"name" => existing} -> existing == name end)
          end)

        has_more = length(items) >= @filter_per_page

        socket =
          socket
          |> assign(loading_key, false)
          |> assign(has_more_key, has_more)
          |> assign(page_key, current_page + 1)
          |> update(assign_key, fn current -> current ++ new_items end)
          |> track_loading(String.to_atom("#{filter_type}_load"), false)

        {:noreply, socket}

      {:error, _} ->
        socket =
          socket
          |> assign(loading_key, false)
          |> assign(has_more_key, false)
          |> track_loading(String.to_atom("#{filter_type}_load"), false)

        {:noreply, socket}
    end
  end

  def handle_event("load_more_search_results", _, socket) do
    if socket.assigns.has_more_items do
      socket =
        socket
        |> track_loading(:more_load, true)
        |> do_load_more()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("search", %{"term" => term}, socket) do
    # First reset all filters
    socket =
      socket
      |> assign(
        selected_director: [],
        selected_sezione: [],
        selected_edizione: [],
        selected_featuring: [],
        first_selected_filter: nil,
        is_keyword_search: true,
        keep_keyword_filtering: true,
        term: term,
        page: 0
      )
      |> track_loading(:search_load, true)

    # Then perform search with only the term
    case Client.find(
           conditions: [%{key: "*", operator: "=", value: term}],
           range: [0, @default_per_page],
           keys: @default_keys,
           total: true
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        socket =
          socket
          |> stream(:search_results, prepare_items(items_to_show), reset: true)
          |> assign(
            has_more_items: has_more,
            current_count: length(items_to_show),
            page: 0
          )
          |> track_loading(:search_load, false)

        # Update metadata for new search results
        case fetch_metadata(socket, [%{key: "*", operator: "=", value: term}]) do
          {:ok, socket} ->
            {:noreply, socket}

          {:error, socket} ->
            {:noreply, socket |> put_flash(:error, l("Error updating filters"))}
        end

      error ->
        {:noreply,
         socket
         |> assign_error(l("Search failed"))
         |> track_loading(:search_load, false)}
    end
  end

  def handle_event("clear_search", _, socket) do
    socket = track_loading(socket, :global_load, true)

    {:noreply,
     socket
     |> assign(@initial_assigns)
     |> stream(:search_results, [], reset: true)
     |> maybe_fetch_initial_results()
     |> track_loading(:global_load, false)}
  end

  def handle_event("clear_filters", _, socket) do
    socket =
      socket
      |> assign(
        term: nil,
        selected_director: [],
        selected_sezione: [],
        selected_edizione: [],
        selected_featuring: [],
        first_selected_filter: nil,
        is_keyword_search: false,
        keep_keyword_filtering: false,
        page: 0
      )
      # Reset the stream first
      |> stream(:search_results, [], reset: true)
      |> track_loading(:global_load, true)

    # Fetch initial results directly instead of using trigger_search
    case Client.find(
           sort: [%{key: "title", operator: "+"}],
           range: [0, @default_per_page],
           keys: @default_keys,
           total: true
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        socket =
          socket
          |> stream(:search_results, prepare_items(items_to_show))
          |> assign(
            has_more_items: has_more,
            current_count: length(items_to_show),
            page: 0
          )
          # Update metadata without conditions to get full lists
          |> update_metadata_with_conditions([])
          |> track_loading(:global_load, false)

        {:noreply, socket}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, l("Error loading results"))
         |> track_loading(:global_load, false)}
    end
  end

  # All helper functions remain unchanged
  defp update_metadata_with_conditions(socket, conditions, current_filter \\ nil) do
    # Code unchanged
    case Client.fetch_grouped_metadata(conditions) do
      {:ok, filtered_metadata} ->
        metadata =
          cond do
            # Keep the current filter's list unchanged
            current_filter != nil ->
              Map.update(filtered_metadata, current_filter, [], fn _new_list ->
                get_current_filter_list(socket, current_filter)
              end)

            socket.assigns.is_keyword_search || socket.assigns.keep_keyword_filtering ->
              filtered_metadata

            socket.assigns.first_selected_filter ->
              key = socket.assigns.first_selected_filter

              case Client.fetch_grouped_metadata([]) do
                {:ok, complete_metadata} ->
                  Map.put(filtered_metadata, key, complete_metadata[key])

                _ ->
                  filtered_metadata
              end

            true ->
              filtered_metadata
          end

        socket
        |> assign(
          available_director: metadata["director"] || [],
          available_sezione: metadata["sezione"] || [],
          available_edizione: metadata["edizione"] || [],
          available_featuring: metadata["featuring"] || []
        )

      _ ->
        socket
        |> put_flash(:error, l("Error updating filters"))
    end
  end

  defp get_current_filter_list(socket, filter_type) do
    case filter_type do
      "director" -> socket.assigns.available_director
      "sezione" -> socket.assigns.available_sezione
      "edizione" -> socket.assigns.available_edizione
      "featuring" -> socket.assigns.available_featuring
      _ -> []
    end
  end

  def fetch_initial_data(socket) do
    debug("Starting initial data fetch")

    socket = track_loading(socket, :initial_load, true)

    case Client.find(
           sort: [%{key: "title", operator: "+"}],
           range: [0, @default_per_page],
           keys: @default_keys,
           total: true
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        debug("Initial data fetch successful, fetching metadata")

        socket
        |> stream(:search_results, prepare_items(items_to_show), reset: true)
        |> assign(
          has_more_items: has_more,
          current_count: length(items_to_show),
          page: 0
        )
        |> then(fn socket ->
          case fetch_metadata(socket, []) do
            {:ok, socket} ->
              socket

            {:error, socket} ->
              # Even if metadata fails, keep the search results
              socket
              |> put_flash(:error, l("Error loading filters"))
          end
        end)
        |> track_loading(:initial_load, false)

      error ->
        debug("Error in initial data fetch: #{inspect(error)}")

        socket
        |> track_loading(:initial_load, false)
        |> put_flash(:error, l("Error loading initial data"))
    end
  end

  defp fetch_metadata(socket, conditions) do
    socket = track_loading(socket, :metadata_load, true)

    case Client.fetch_grouped_metadata(conditions, per_page: @filter_per_page) do
      {:ok, metadata} ->
        {:ok,
         socket
         |> assign(
           available_director: Map.get(metadata, "director", []),
           available_sezione: Map.get(metadata, "sezione", []),
           available_edizione: Map.get(metadata, "edizione", []),
           available_featuring: Map.get(metadata, "featuring", [])
         )
         |> track_loading(:metadata_load, false)}

      {:error, reason} ->
        debug("Metadata fetch error: #{inspect(reason)}")
        {:error, socket |> track_loading(:metadata_load, false)}
    end
  end

  defp maybe_fetch_initial_results(socket) do
    socket = track_loading(socket, :global_load, true)

    case Client.find(
           sort: [%{key: "title", operator: "+"}],
           # Use range instead of page/per_page
           range: [0, @default_per_page],
           keys: @default_keys
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        # First update the stream and basic assigns
        socket =
          socket
          |> stream(:search_results, prepare_items(items_to_show), reset: true)
          |> assign(
            has_more_items: has_more,
            current_count: length(items_to_show),
            page: 0
          )

        # Then update metadata with current conditions
        conditions = build_search_conditions(socket.assigns)

        socket
        |> update_metadata_with_conditions(conditions)
        |> track_loading(:global_load, false)

      _ ->
        track_loading(socket, :global_load, false)
    end
  end

  # def toggle_filter(socket, filter_type, value) do
  #   debug("Toggling filter: #{filter_type} = #{value}")
  #   {:noreply, socket}
  # end

  defp toggle_filter(socket, filter_type, value)
       when filter_type in @filter_types and is_binary(value) do
    # Code unchanged
    filter_key =
      case filter_type do
        "sezione" -> :selected_sezione
        "edizione" -> :selected_edizione
        "featuring" -> :selected_featuring
        "director" -> :selected_director
      end

    current_filters = Map.get(socket.assigns, filter_key, [])

    {updated_filters, first_filter} =
      if value in current_filters do
        filters = List.delete(current_filters, value)

        first_filter =
          if filters == [] && socket.assigns.first_selected_filter == filter_type do
            nil
          else
            socket.assigns.first_selected_filter
          end

        {filters, first_filter}
      else
        first_filter =
          case socket.assigns.first_selected_filter do
            nil -> filter_type
            existing -> existing
          end

        {[value | current_filters], first_filter}
      end

    socket =
      socket
      |> assign(filter_key, updated_filters)
      |> assign(:first_selected_filter, first_filter)
      |> track_loading(:global_load, true)

    conditions = build_search_conditions(socket.assigns)

    case Client.find(
           conditions: conditions,
           range: [0, @default_per_page],
           keys: @default_keys,
           total: true
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        socket
        |> stream(:search_results, prepare_items(items_to_show), reset: true)
        |> assign(
          has_more_items: has_more,
          current_count: length(items_to_show),
          page: 0
        )
        # Pass current_filter to preserve its list
        |> update_metadata_with_conditions(conditions, filter_type)
        |> track_loading(:global_load, false)

      _ ->
        socket
        |> put_flash(:error, l("Error updating results"))
        |> track_loading(:global_load, false)
    end
  end

  defp track_loading(socket, state, is_loading) do
    current_loading = Map.get(socket.assigns, :loading_states, MapSet.new())

    new_loading =
      if is_loading do
        MapSet.put(current_loading, state)
      else
        MapSet.delete(current_loading, state)
      end

    socket
    |> assign(:loading_states, new_loading)
    |> assign(:loading, MapSet.size(new_loading) > 0)
  end

  defp build_search_conditions(%{
         term: term,
         selected_director: directors,
         selected_sezione: sezione,
         selected_edizione: edizione,
         selected_featuring: featuring
       }) do
    filters =
      []
      |> add_filter_condition("director", directors)
      |> add_filter_condition("sezione", sezione)
      |> add_filter_condition("edizione", edizione)
      |> add_filter_condition("featuring", featuring)
      |> Enum.reject(&is_nil/1)

    case {term, filters} do
      {nil, []} ->
        []

      {term, []} when is_binary(term) and term != "" ->
        [%{key: "*", operator: "=", value: term}]

      {nil, [single]} ->
        [single]

      {nil, multiple} when length(multiple) > 0 ->
        [%{conditions: multiple, operator: "&"}]

      {term, filters} when is_binary(term) and term != "" ->
        [
          %{
            conditions: [%{key: "*", operator: "=", value: term} | filters],
            operator: "&"
          }
        ]
    end
  end

  defp add_filter_condition(conditions, _type, []), do: conditions

  defp add_filter_condition(conditions, type, [single]),
    do: [%{key: type, operator: "==", value: single} | conditions]

  defp add_filter_condition(conditions, type, values) when length(values) > 0,
    do: [
      %{
        conditions: Enum.map(values, &%{key: type, operator: "==", value: &1}),
        # Use OR operator for multiple values of same type
        operator: "|"
      }
      | conditions
    ]

  defp do_load_more(socket) do
    socket = track_loading(socket, :more_load, true)
    next_page = socket.assigns.page + 1
    conditions = build_search_conditions(socket.assigns)
    start_index = next_page * @default_per_page

    case Client.find(
           conditions: conditions,
           range: [start_index, start_index + @default_per_page],
           keys: @default_keys
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        socket
        |> stream(:search_results, prepare_items(items_to_show))
        |> assign(
          page: next_page,
          has_more_items: has_more,
          current_count: socket.assigns.current_count + length(items_to_show)
        )
        |> track_loading(:more_load, false)
        # Make sure to clear the legacy loading state too
        |> track_loading(:global_load, false)

      other ->
        error(other, l("Failed to load more"))

        socket
        |> assign_error(l("Failed to load more"))
        |> track_loading(:more_load, false)
        # Clear both loading states
        |> track_loading(:global_load, false)
    end
  end

  defp is_loading?(socket, state) do
    socket.assigns
    |> Map.get(:loading_states, MapSet.new())
    |> MapSet.member?(state)
  end

  defp handle_pagination_results(items, per_page) when is_list(items) do
    items_received = length(items)

    if items_received > per_page do
      {Enum.take(items, per_page), true}
    else
      {items, false}
    end
  end

  defp prepare_items(items) do
    items
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      stable_id = Utils.generate_stable_id(item)
      # Add an order field to help maintain sequence
      item
      |> Map.put("stable_id", stable_id)
      |> Map.put("order", index)
    end)
  end

  # If this is not defined in the original code, add it to handle error assigns
  # defp assign_error(socket, message) do
  #   socket
  #   |> assign(:error, message)
  # end
end
