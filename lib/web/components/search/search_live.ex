defmodule Bonfire.PanDoRa.Web.SearchLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Auth
  alias Bonfire.PanDoRa.Utils
  @behaviour Bonfire.UI.Common.LiveHandler

  # Fallback if get_filter_keys returns empty (fixed list: director, featuring, language, country, year, keywords)
  @filter_types_fallback ~w(director featuring language country year keywords)
  # Essential fields always requested from find
  @essential_keys ~w(title id item_id public_id duration)
  @default_per_page 20
  @filter_per_page 10

  prop term, :string
  prop current_user, :any

  @initial_assigns %{
    page: 0,
    term: nil,
    loading: false,
    has_more_items: true,
    current_count: 0,
    per_page: @default_per_page,
    # Filter state (keyed by field name, uses fixed filter types)
    filter_types: [],
    available_filters: %{},
    current_filters: %{},
    filter_pages: %{},
    filter_loading: %{},
    filter_has_more: %{},
    first_selected_filter: nil,
    is_keyword_search: false,
    keep_keyword_filtering: false,
    error: nil,
    # Precomputed for template (no <% %> needed)
    filter_sections: [],
    active_filter_badges: [],
    selected_by_field: %{}
  }

  def mount(socket) do
    {:ok,
     socket
     |> stream_configure(:search_results,
       dom_id: &"result-#{&1["stable_id"] || Utils.generate_stable_id(&1)}"
     )
     |> stream(:search_results, [])
     |> assign(@initial_assigns)
     |> assign(:loading_states, MapSet.new())
     |> track_loading(:initial_load, true)}
  end

  def update(assigns, socket) do
    debug("Updating SearchComponent")

    socket = assign(socket, assigns)

    socket =
      if not is_nil(assigns[:term]) and assigns.term != "" do
        do_initial_search(socket, assigns.term)
      else
        fetch_initial_data(socket)
      end

    socket =
      socket
      |> assign(:pandora_token, Auth.pandora_token(current_user: socket.assigns[:current_user]))
      |> assign(:pandora_base_url, String.trim_trailing(Client.get_pandora_url() || "", "/"))
      |> assign_filter_by_field_assigns()

    {:ok, socket}
  end

  # Build data for template so we use only {#for} and { } (no <% %>).
  # Logic in component, template for presentation.
  defp assign_filter_by_field_assigns(socket) do
    filter_types = socket.assigns[:filter_types] || @filter_types_fallback
    available_filters = socket.assigns[:available_filters] || %{}
    current_filters = socket.assigns[:current_filters] || %{}
    filter_pages = socket.assigns[:filter_pages] || %{}
    filter_loading = socket.assigns[:filter_loading] || %{}

    filter_sections =
      Enum.map(filter_types, fn type ->
        list = Map.get(available_filters, type, [])

        # Normalize name to string so phx-value-id and section.selected match (year can be int from API)
        available =
          Enum.map(list, fn
            %{"name" => n, "items" => c} -> %{name: to_string(n), items: c}
            %{name: n, items: c} -> %{name: to_string(n), items: c}
            other -> %{name: inspect(other), items: 0}
          end)

        %{
          id: type,
          label: Gettext.gettext(Bonfire.Common.Localise.Gettext, String.capitalize(type)),
          available: available,
          selected: Map.get(current_filters, type, []),
          page: Map.get(filter_pages, type, 0),
          loading: Map.get(filter_loading, type, false)
        }
      end)

    active_filter_badges =
      Enum.map(filter_types, fn type ->
        values = Map.get(current_filters, type, [])
        label = Gettext.gettext(Bonfire.Common.Localise.Gettext, String.capitalize(type))
        %{id: type, label: label, values: values}
      end)

    selected_by_field =
      Map.new(filter_types, fn type ->
        {type, Map.get(current_filters, type, [])}
      end)

    socket
    |> assign(:filter_sections, filter_sections)
    |> assign(:active_filter_badges, active_filter_badges)
    |> assign(:selected_by_field, selected_by_field)
  end

  # ── Initial data load ──────────────────────────────────────────────────────

  defp do_initial_search(socket, term) do
    socket = track_loading(socket, :search_load, true)
    conditions = build_search_conditions(%{term: term, current_filters: socket.assigns.current_filters})
    keys = build_request_keys(socket)

    case Client.find(
           conditions: conditions,
           range: [0, @default_per_page],
           keys: keys,
           total: true,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items} = data} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        socket =
          socket
          |> maybe_assign_context(data)
          |> stream(:search_results, prepare_items(items_to_show), reset: true)
          |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
          |> track_loading(:search_load, false)

        case fetch_metadata(socket, conditions) do
          {:ok, updated_socket} -> updated_socket
          {:error, error_socket} -> assign_error(error_socket, l("Error updating filters"))
        end

      other ->
        error(other, "Search failed")

        socket
        |> assign_error(l("Search failed"))
        |> track_loading(:search_load, false)
    end
  end

  def do_component_search(socket, term) do
    socket = track_loading(socket, :search_load, true)
    conditions = build_search_conditions(%{term: term, current_filters: socket.assigns.current_filters})
    keys = build_request_keys(socket)

    case Client.find(
           conditions: conditions,
           range: [0, @default_per_page],
           keys: keys,
           total: true,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items} = data} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        socket =
          socket
          |> maybe_assign_context(data)
          |> stream(:search_results, prepare_items(items_to_show), reset: true)
          |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
          |> track_loading(:search_load, false)

        case fetch_metadata(socket, conditions) do
          {:ok, updated_socket} -> {:noreply, updated_socket}
          {:error, error_socket} -> {:noreply, put_flash(error_socket, :error, l("Error updating filters"))}
        end

      other ->
        error(other, "Search failed")
        {:noreply, socket |> assign_error(l("Search failed")) |> track_loading(:search_load, false)}
    end
  end

  # ── handle_info ────────────────────────────────────────────────────────────

  def handle_info({:do_component_search, id, term}, socket) when socket.id == id do
    debug("Searching for #{term} in component #{id}")
    {:noreply, do_initial_search(socket, term)}
  end

  def handle_info({:do_search, term}, socket) do
    {:noreply, do_initial_search(socket, term)}
  end

  def handle_info({:set_loading_state, state}, socket) do
    {:noreply, track_loading(socket, :global_load, state)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, socket) do
    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    debug("SearchComponent received unexpected message: #{inspect(msg)}")
    {:noreply, socket}
  end

  # ── handle_event ───────────────────────────────────────────────────────────

  # Specific handler for generic "filter_by_field" events from extra_metadata badges.
  # Map API key to filter type (e.g. "keyword" -> "keywords") for UI consistency.
  def handle_event("filter_by_field", %{"field" => field, "id" => value}, socket)
      when is_binary(field) and is_binary(value) do
    filter_type = Client.api_key_to_filter_type(field)
    {:noreply, toggle_filter(socket, filter_type, value)}
  end

  # Generic handler for any "filter_by_X" event emitted by the filter panel
  def handle_event("filter_by_" <> filter_type, %{"id" => value} = _params, socket)
      when is_binary(filter_type) and is_binary(value) do
    {:noreply, toggle_filter(socket, filter_type, value)}
  end

  # load_more_search_results must come before the generic load_more_X handler
  def handle_event("load_more_search_results", _, socket) do
    if socket.assigns.has_more_items do
      {:noreply, socket |> track_loading(:more_load, true) |> do_load_more()}
    else
      {:noreply, socket}
    end
  end

  # Generic infinite scroll for any filter column
  def handle_event("load_more_" <> filter_type, _params, socket) do
    page_key = filter_type
    current_page = get_in(socket.assigns, [:filter_pages, filter_type]) || 0
    conditions = build_search_conditions(socket.assigns)

    socket =
      socket
      |> update(:filter_loading, &Map.put(&1, filter_type, true))
      |> track_loading(String.to_atom("#{filter_type}_load"), true)

    case Client.fetch_grouped_metadata(conditions,
           field: filter_type,
           page: current_page + 1,
           per_page: @filter_per_page,
           current_user: current_user(socket)
         ) do
      {:ok, metadata} ->
        items = Map.get(metadata, filter_type, [])
        current_items = get_in(socket.assigns, [:available_filters, filter_type]) || []

        new_items =
          Enum.filter(items, fn %{"name" => name} ->
            not Enum.any?(current_items, fn %{"name" => existing} -> existing == name end)
          end)

        has_more = length(items) >= @filter_per_page

        socket =
          socket
          |> update(:filter_loading, &Map.put(&1, filter_type, false))
          |> update(:filter_has_more, &Map.put(&1, filter_type, has_more))
          |> update(:filter_pages, &Map.put(&1, page_key, current_page + 1))
          |> update(:available_filters, &Map.update(&1, filter_type, new_items, fn cur -> cur ++ new_items end))
          |> track_loading(String.to_atom("#{filter_type}_load"), false)

        {:noreply, socket}

      {:error, _} ->
        socket =
          socket
          |> update(:filter_loading, &Map.put(&1, filter_type, false))
          |> update(:filter_has_more, &Map.put(&1, filter_type, false))
          |> track_loading(String.to_atom("#{filter_type}_load"), false)

        {:noreply, socket}
    end
  end

  def handle_event("search", %{"term" => term}, socket) do
    conditions = [%{key: "*", operator: "=", value: term}]
    socket =
      socket
      |> assign(
        current_filters: %{},
        first_selected_filter: nil,
        is_keyword_search: true,
        keep_keyword_filtering: true,
        term: term,
        page: 0
      )
      |> track_loading(:search_load, true)

    case Client.find(
           conditions: conditions,
           range: [0, @default_per_page],
           keys: build_request_keys(socket),
           total: true,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        socket =
          socket
          |> stream(:search_results, prepare_items(items_to_show), reset: true)
          |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
          |> track_loading(:search_load, false)

        case fetch_metadata(socket, conditions) do
          {:ok, socket} -> {:noreply, socket}
          {:error, socket} -> {:noreply, put_flash(socket, :error, l("Error updating filters"))}
        end

      _ ->
        {:noreply,
         socket
         |> assign_error(l("Search failed"))
         |> track_loading(:search_load, false)}
    end
  end

  def handle_event("clear_search", _, socket) do
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
        current_filters: %{},
        first_selected_filter: nil,
        is_keyword_search: false,
        keep_keyword_filtering: false,
        page: 0
      )
      |> stream(:search_results, [], reset: true)
      |> track_loading(:global_load, true)

    keys = build_request_keys(socket)

    case Client.find(
           sort: [%{key: "title", operator: "+"}],
           range: [0, @default_per_page],
           keys: keys,
           total: true,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        socket =
          socket
          |> stream(:search_results, prepare_items(items_to_show))
          |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
          |> update_available_filters([])
          |> track_loading(:global_load, false)

        {:noreply, socket}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, l("Error loading results"))
         |> track_loading(:global_load, false)}
    end
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  def fetch_initial_data(socket) do
    debug("Starting initial data fetch")
    socket = socket |> track_loading(:initial_load, true) |> load_filter_types()
    keys = build_request_keys(socket)

    case Client.find(
           sort: [%{key: "title", operator: "+"}],
           range: [0, @default_per_page],
           keys: keys,
           total: true,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items} = data} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        socket
        |> maybe_assign_context(data)
        |> stream(:search_results, prepare_items(items_to_show), reset: true)
        |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
        |> then(fn socket ->
          case fetch_metadata(socket, []) do
            {:ok, socket} -> socket
            {:error, socket} -> put_flash(socket, :error, l("Error loading filters"))
          end
        end)
        |> track_loading(:initial_load, false)

      other ->
        error(other, "Error in initial data fetch")

        socket
        |> track_loading(:initial_load, false)
        |> put_flash(:error, l("Error loading initial data"))
    end
  end

  # Fetch dynamic filter types from Pandora init API; fall back to @filter_types_fallback
  defp load_filter_types(socket) do
    filter_types = Client.get_filter_keys(current_user: current_user(socket))
    types = if is_list(filter_types) and filter_types != [], do: filter_types, else: @filter_types_fallback
    assign(socket, :filter_types, types)
  end

  # Build the list of item keys to request from find (essential + filterable).
  # Uses filter_type_to_api_key so we request "keyword" not "keywords".
  defp build_request_keys(socket) do
    filter_types = socket.assigns[:filter_types] || @filter_types_fallback
    api_keys = Enum.map(filter_types, &Client.filter_type_to_api_key/1)
    (@essential_keys ++ api_keys) |> Enum.uniq()
  end

  defp fetch_metadata(socket, conditions) do
    socket = track_loading(socket, :metadata_load, true)
    filter_types = socket.assigns[:filter_types] || @filter_types_fallback

    case Client.fetch_grouped_metadata(conditions,
           fields: filter_types,
           per_page: @filter_per_page,
           current_user: current_user(socket)
         ) do
      {:ok, metadata} ->
        available_filters =
          Enum.reduce(filter_types, %{}, fn type, acc ->
            Map.put(acc, type, Map.get(metadata, type, []))
          end)

        filter_has_more =
          Enum.reduce(filter_types, %{}, fn type, acc ->
            Map.put(acc, type, length(Map.get(available_filters, type, [])) >= @filter_per_page)
          end)

        {:ok,
         socket
         |> assign(:available_filters, available_filters)
         |> assign(:filter_has_more, filter_has_more)
         |> track_loading(:metadata_load, false)}

      {:error, reason} ->
        debug("Metadata fetch error: #{inspect(reason)}")
        {:error, socket |> track_loading(:metadata_load, false)}
    end
  end

  # Re-fetch available options for each filter column, optionally preserving the list for
  # `preserved_field` (the field the user just filtered by, so it doesn't collapse).
  defp update_available_filters(socket, conditions, preserved_field \\ nil) do
    filter_types = socket.assigns[:filter_types] || @filter_types_fallback

    case Client.fetch_grouped_metadata(conditions,
           fields: filter_types,
           current_user: current_user(socket)
         ) do
      {:ok, filtered_metadata} ->
        current_available = socket.assigns[:available_filters] || %{}

        should_fetch_full_for =
          cond do
            preserved_field != nil -> nil
            socket.assigns.first_selected_filter -> socket.assigns.first_selected_filter
            true -> nil
          end

        full_metadata =
          if should_fetch_full_for do
            case Client.fetch_grouped_metadata([],
                   fields: filter_types,
                   current_user: current_user(socket)
                 ) do
              {:ok, m} -> m
              _ -> %{}
            end
          else
            %{}
          end

        new_available =
          Enum.reduce(filter_types, %{}, fn type, acc ->
            value =
              cond do
                type == preserved_field ->
                  Map.get(current_available, type, [])

                type == should_fetch_full_for ->
                  Map.get(full_metadata, type, Map.get(filtered_metadata, type, []))

                true ->
                  Map.get(filtered_metadata, type, [])
              end

            Map.put(acc, type, value)
          end)

        assign(socket, :available_filters, new_available)

      _ ->
        put_flash(socket, :error, l("Error updating filters"))
    end
  end

  defp maybe_fetch_initial_results(socket) do
    socket = track_loading(socket, :global_load, true)
    keys = build_request_keys(socket)

    case Client.find(
           sort: [%{key: "title", operator: "+"}],
           range: [0, @default_per_page],
           keys: keys,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        socket
        |> stream(:search_results, prepare_items(items_to_show), reset: true)
        |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
        |> update_available_filters(build_search_conditions(socket.assigns))
        |> track_loading(:global_load, false)

      _ ->
        track_loading(socket, :global_load, false)
    end
  end

  # Toggle a filter value in/out of current_filters and re-run the search.
  # On find failure: rollback current_filters to avoid inconsistent state.
  defp toggle_filter(socket, filter_type, value)
       when is_binary(filter_type) and is_binary(value) do
    current_filters = socket.assigns[:current_filters] || %{}
    current_values = Map.get(current_filters, filter_type, [])

    {updated_values, first_filter} =
      if value in current_values do
        values = List.delete(current_values, value)

        first =
          if values == [] and socket.assigns.first_selected_filter == filter_type,
            do: nil,
            else: socket.assigns.first_selected_filter

        {values, first}
      else
        first = socket.assigns.first_selected_filter || filter_type
        {[value | current_values], first}
      end

    new_filters = Map.put(current_filters, filter_type, updated_values)
    previous_filters = current_filters
    previous_first = socket.assigns[:first_selected_filter]

    socket =
      socket
      |> assign(:current_filters, new_filters)
      |> assign(:first_selected_filter, first_filter)
      |> track_loading(:global_load, true)

    conditions = build_search_conditions(socket.assigns)
    keys = build_request_keys(socket)

    case Client.find(
           conditions: conditions,
           range: [0, @default_per_page],
           keys: keys,
           total: true,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} = handle_pagination_results(items, @default_per_page)

        socket
        |> stream(:search_results, prepare_items(items_to_show), reset: true)
        |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
        |> update_available_filters(conditions, filter_type)
        |> track_loading(:global_load, false)

      _ ->
        # Rollback: restore previous filters to avoid inconsistent state
        socket
        |> assign(:current_filters, previous_filters)
        |> assign(:first_selected_filter, previous_first)
        |> put_flash(:error, l("Error updating results"))
        |> track_loading(:global_load, false)
    end
  end

  defp track_loading(socket, state, is_loading) do
    current_loading = Map.get(socket.assigns, :loading_states, MapSet.new())

    new_loading =
      if is_loading,
        do: MapSet.put(current_loading, state),
        else: MapSet.delete(current_loading, state)

    socket
    |> assign(:loading_states, new_loading)
    |> assign(:loading, MapSet.size(new_loading) > 0)
  end

  # Build Pandora API conditions. Legacy filter.js uses flat conditions + "==" for all.
  # query.conditions = [c1, c2, ...], query.operator = "&"
  defp build_search_conditions(%{term: term, current_filters: current_filters}) do
    filter_conditions =
      (current_filters || %{})
      |> Enum.flat_map(fn {type, values} ->
        api_key = Client.filter_type_to_api_key(type)
        op = Client.operator_for_filter_type(type)

        case values do
          [] -> []
          [single] -> [normalize_condition_value(api_key, single, type)]
          multiple -> [%{conditions: Enum.map(multiple, &normalize_condition_value(api_key, &1, type)), operator: "|"}]
        end
      end)

    case {term, filter_conditions} do
      {nil, []} ->
        []

      {term, []} when is_binary(term) and term != "" ->
        [%{key: "*", operator: "=", value: term}]

      {nil, [single]} ->
        [single]

      # Multiple filters: flat array like legacy (query.operator "&" combines them)
      {nil, multiple} when length(multiple) > 0 ->
        multiple

      {term, filters} when is_binary(term) and term != "" ->
        [%{key: "*", operator: "=", value: term} | filters]
    end
  end

  # Year may need integer for API (Pandora stores as number)
  defp normalize_condition_value(api_key, value, "year") when is_binary(value) do
    op = Client.operator_for_filter_type("year")
    case Integer.parse(value) do
      {num, ""} -> %{key: api_key, operator: op, value: num}
      _ -> %{key: api_key, operator: op, value: value}
    end
  end

  defp normalize_condition_value(api_key, value, type) do
    op = Client.operator_for_filter_type(type)
    %{key: api_key, operator: op, value: value}
  end

  # Fallback: called with raw assigns map
  defp build_search_conditions(assigns) when is_map(assigns) do
    build_search_conditions(%{
      term: Map.get(assigns, :term),
      current_filters: Map.get(assigns, :current_filters, %{})
    })
  end

  defp do_load_more(socket) do
    socket = track_loading(socket, :more_load, true)
    next_page = socket.assigns.page + 1
    conditions = build_search_conditions(socket.assigns)
    start_index = next_page * @default_per_page
    keys = build_request_keys(socket)

    case Client.find(
           conditions: conditions,
           range: [start_index, start_index + @default_per_page],
           keys: keys,
           current_user: current_user(socket)
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
        |> track_loading(:global_load, false)

      other ->
        error(other, l("Failed to load more"))

        socket
        |> assign_error(l("Failed to load more"))
        |> track_loading(:more_load, false)
        |> track_loading(:global_load, false)
    end
  end

  defp handle_pagination_results(items, per_page) when is_list(items) do
    if length(items) > per_page,
      do: {Enum.take(items, per_page), true},
      else: {items, false}
  end

  defp prepare_items(items) do
    items
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      item
      |> Map.put("stable_id", Utils.generate_stable_id(item))
      |> Map.put("order", index)
    end)
  end
end
