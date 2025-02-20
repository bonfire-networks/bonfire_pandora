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
  @filter_types ~w(director sezione edizione featuring)
  @default_per_page 20
  @default_keys ~w(title id item_id public_id director sezione edizione featuring duration)

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
    available_sezione: [],
    available_edizione: [],
    available_featuring: [],
    selected_directors: [],
    selected_sezione: [],
    selected_edizione: [],
    selected_featuring: [],
    first_selected_filter: nil,
    is_keyword_search: false,
    keep_keyword_filtering: false,
    error: nil
  }

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    debug("Mounting SearchLive")

    socket =
      socket
      |> stream_configure(:search_results,
        dom_id: &"result-#{&1["stable_id"] || generate_stable_id(&1)}"
      )
      |> stream(:search_results, [])
      |> assign(@initial_assigns)
      |> assign(:nav_items, Bonfire.Common.ExtensionModule.default_nav())
      # Set initial loading state
      |> assign(:loading, true)

    if connected?(socket) do
      send(self(), :load_initial_data)
      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  def handle_info(:load_initial_data, socket) do
    {:noreply, fetch_initial_data(socket)}
  end

  # Catch-all clause for unexpected messages
  # def handle_info(msg, socket) do
  #   debug("SearchLive received unexpected message: #{inspect(msg)}")
  #   {:noreply, socket}
  # end

  # Keep your existing handle_params implementation
  def handle_params(%{"term" => term}, _, socket) do
    if connected?(socket) do
      do_search(socket, term)
    else
      {:noreply, assign(socket, term: term)}
    end
  end

  def handle_params(_, _, socket), do: {:noreply, socket}

    # Handle specific filter events
    def handle_event("filter_by_sezione", %{"id" => value} = params, socket) when is_binary(value) do
      {:noreply, toggle_filter(socket, "sezione", value)}
    end

    def handle_event("filter_by_edizione", %{"id" => value} = params, socket) when is_binary(value) do
      {:noreply, toggle_filter(socket, "edizione", value)}
    end

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
        selected_sezione: socket.assigns.selected_sezione,
        selected_edizione: socket.assigns.selected_edizione,
        selected_featuring: socket.assigns.selected_featuring
      })

    # Update metadata with current conditions
    socket = update_metadata_with_conditions(socket, conditions)

    trigger_search(socket)
  end



  # New function to update metadata with current conditions
  defp update_metadata_with_conditions(socket, conditions) do
    case Client.fetch_grouped_metadata(conditions) do
      {:ok, filtered_metadata} ->
        metadata = cond do
          socket.assigns.is_keyword_search || socket.assigns.keep_keyword_filtering ->
            filtered_metadata
          socket.assigns.first_selected_filter ->
            case Client.fetch_grouped_metadata([]) do
              {:ok, complete_metadata} ->
                # Keep complete metadata for first filter, filtered for others
                key = case socket.assigns.first_selected_filter do
                  "director" -> "director"
                  "sezione" -> "sezione"
                  "edizione" -> "edizione"
                  "featuring" -> "featuring"
                end
                Map.put(filtered_metadata, key, complete_metadata[key])
              _ ->
                filtered_metadata
            end
          true ->
            filtered_metadata
        end

        socket
        |> assign(
          available_directors: metadata["director"] || [],
          available_sezione: metadata["sezione"] || [],
          available_edizione: metadata["edizione"] || [],
          available_featuring: metadata["featuring"] || []
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

  def handle_event("search", %{"term" => term}, socket) do
    socket =
      socket
      |> assign(
        selected_directors: [],
        selected_sezione: [],
        selected_edizione: [],
        selected_featuring: [],
        term: term,
        is_keyword_search: true,
        keep_keyword_filtering: true,
        first_selected_filter: nil
      )
      |> reset_pagination()
      |> set_loading_state(true)
      |> trigger_search()

    {:noreply, socket}
  end

  def handle_event("clear_search", _, socket) do
    socket = set_loading_state(socket, true)

    {:noreply,
     socket
     |> assign(@initial_assigns)
     |> stream(:search_results, [], reset: true)
     |> maybe_fetch_initial_results()
     |> set_loading_state(false)}
  end

  def handle_event("clear_filters", _, socket) do
    socket =
      socket
      |> assign(
        term: nil,
        selected_directors: [],
        selected_sezione: [],
        selected_edizione: [],
        selected_featuring: [],
        first_selected_filter: nil,
        is_keyword_search: false,
        keep_keyword_filtering: false
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
    socket = set_loading_state(socket, true)

    case Client.fetch_grouped_metadata() do
      {:ok, metadata} ->
        {:noreply,
         socket
         |> assign_metadata(metadata)
         |> set_loading_state(false)}

      _ ->
        {:noreply, set_loading_state(socket, false)}
    end
  end

  def handle_info({:set_loading_state, state}, socket) do
    IO.inspect(state, label: "Loading stateeee")
    {:noreply, assign(socket, loading: state)}
  end

  def handle_info({:do_search, term}, socket) do
    do_search(socket, term)
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

  defp fetch_initial_data(socket) do
    case Client.fetch_grouped_metadata() do
      {:ok, metadata} ->
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
            socket
            |> handle_search_success(items, total, [])  # Pass empty conditions for initial load
            |> assign(:loading, false)

          _ ->
            socket |> assign(:loading, false)
        end

      metadata when is_map(metadata) ->
        socket
        |> assign_metadata(metadata)
        |> assign(:loading, false)

      _ ->
        socket |> assign(:loading, false)
    end
  end

  defp maybe_fetch_initial_results(socket) do
    socket = set_loading_state(socket, true)

    case Client.find(
           sort: [%{key: "title", operator: "+"}],
           page: 0,
           per_page: @default_per_page,
           keys: @default_keys
         ) do
      {:ok, %{items: items, total: total}} ->
        socket
        |> handle_search_success(items, total, [])  # Pass empty conditions for initial load
        |> set_loading_state(false)

      _ ->
        set_loading_state(socket, false)
    end
  end

  defp toggle_filter(socket, filter_type, value) when filter_type in @filter_types and is_binary(value) do
    # Handle Italian words that don't follow English pluralization
    filter_key = case filter_type do
      "sezione" -> :selected_sezione
      "edizione" -> :selected_edizione
      "featuring" -> :selected_featuring
      other -> String.to_existing_atom("selected_#{other}s")
    end
    current_filters = Map.get(socket.assigns, filter_key, [])

    # Only switch off keyword search mode, keep the filtering
    socket = if socket.assigns.is_keyword_search do
      assign(socket, :is_keyword_search, false)
    else
      socket
    end

    # Determine if this is the first filter being selected
    {updated_filters, first_filter} =
      if value in current_filters do
        filters = List.delete(current_filters, value)
        first_filter = if filters == [] && socket.assigns.first_selected_filter == filter_type do
          nil  # Reset first filter if removing last value of that type
        else
          socket.assigns.first_selected_filter
        end
        {filters, first_filter}
      else
        first_filter = case socket.assigns.first_selected_filter do
          nil -> filter_type  # This is the first filter
          existing -> existing  # Keep existing first filter
        end
        {[value | current_filters], first_filter}
      end

    socket
    |> assign(filter_key, updated_filters)
    |> assign(:first_selected_filter, first_filter)
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
    socket = assign(socket, :loading, true)
    send(self(), {:do_search, socket.assigns.term})
    socket
  end

  defp build_search_conditions(%{
         term: term,
         selected_directors: directors,
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
        operator: "|"  # Use OR operator for multiple values of same type
      }
      | conditions
    ]

  # Keep your existing implementations but update state management
  defp do_search(socket, term) do
    conditions =
      build_search_conditions(%{
        term: term,
        selected_directors: socket.assigns.selected_directors,
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
      {:ok, %{items: items, total: total}} ->
        socket =
          socket
          |> handle_search_success(items, total, conditions)  # Pass conditions to handle_search_success
          |> assign(:loading, false)

        {:noreply, socket}

      other ->
        error(other, "Search failed")

        {:noreply,
         socket
         |> assign_error(l("Search failed"))
         |> assign(:loading, false)}
    end
  end

  # Update handle_search_success to handle metadata fetching
  defp handle_search_success(socket, items, total, conditions) do
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
        has_more_items: current_count == @default_per_page,
        error: nil
      )

    # Single metadata update with proper handling of first selected filter
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
      available_sezione: metadata["sezione"] || [],
      available_edizione: metadata["edizione"] || [],
      available_featuring: metadata["featuring"] || []
    )
  end

  defp handle_search_error(socket, error) do
    debug("Search error: #{inspect(error)}")

    socket
    |> assign(
      error: error,
      loading: false,
      current_count: 0,
      total_count: 0,
      has_more_items: false
    )
  end

  defp do_load_more(socket) do
    next_page = socket.assigns.page + 1
    conditions = build_search_conditions(socket.assigns)

    case Client.find(
           conditions: conditions,
           range: calculate_page_range(next_page),
           keys: @default_keys,
           total: true
         ) do
      {:ok, %{items: items, total: total}} ->
        new_count = socket.assigns.current_count + length(items)

        socket
        |> stream(:search_results, prepare_items(items))
        |> assign(
          page: next_page,
          current_count: new_count,
          total_count: total,
          has_more_items: length(items) == @default_per_page,
          # Reset loading state after success
          loading: false
        )
        |> update_metadata_with_conditions(conditions)  # Update metadata with current conditions

      other ->
        error(other, "Failed to load more")

        socket
        |> assign_error(l("Failed to load more"))
        # Reset loading state after error
        |> assign(:loading, false)
    end
  end

  defp calculate_page_range(page) do
    start_index = page * @default_per_page
    [start_index, start_index + @default_per_page]
  end

  defp prepare_items(items) do
    items
    |> Enum.map(fn item ->
      Map.put(item, "stable_id", generate_stable_id(item))
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
