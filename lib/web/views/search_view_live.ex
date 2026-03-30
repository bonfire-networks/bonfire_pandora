defmodule Bonfire.PanDoRa.Web.SearchViewLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Auth
  alias Bonfire.PanDoRa.Utils
  alias Bonfire.PanDoRa.Web.SearchLogic
  @behaviour Bonfire.UI.Common.LiveHandler

  declare_extension("Federated Archives",
    icon: "mingcute:microscope-fill",
    emoji: "🔬",
    description: "Federated archives alliance",
    default_nav: [__MODULE__]
  )

  declare_nav_link("Search archive",
    href: "/archive",
    icon: "carbon:document"
  )

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:force_live, true)
      |> assign(:page_title, "Search in your archive")
      |> assign(:term, nil)
      |> assign(:loading, false)
      |> assign(:loading_states, MapSet.new())
      |> assign(:filter_types, [])
      |> assign(:available_filters, %{})
      |> assign(:effective_api_keys, %{})
      |> assign(:current_filters, %{})
      |> assign(:filter_pages, %{})
      |> assign(:filter_loading, %{})
      |> assign(:filter_has_more, %{})
      |> assign(:page, 0)
      |> assign(:has_more_items, true)
      |> assign(:current_count, 0)
      |> assign(:filter_sections, [])
      |> assign(:active_filter_badges, [])
      |> assign(:selected_by_field, %{})
      |> assign(:error, nil)
      |> stream_configure(:search_results,
        dom_id: &"result-#{&1["stable_id"] || Utils.generate_stable_id(&1)}"
      )
      |> stream(:search_results, [])

    {:ok, socket}
  end

  # Query params like /archive?director=Name&year=2020 mirror the in-app filter model (same keys as
  # Movie info widget and search sidebar). Reserved keys are ignored for filter extraction.
  def handle_params(params, _uri, socket) when is_map(params) do
    q = stringify_query_params(params)
    term = normalize_term(Map.get(q, "term"))
    term? = term not in [nil, ""]
    filter_map = filters_from_query_params(q)

    socket =
      cond do
        term? ->
          socket
          |> assign(:term, term)
          |> assign(:current_filters, filter_map)
          |> do_initial_search(term)

        map_size(filter_map) > 0 ->
          socket
          |> assign(:term, nil)
          |> assign(:current_filters, filter_map)
          |> apply_query_filters_search()

        true ->
          socket
          |> assign(:term, nil)
          |> then(fn s ->
            if not data_loaded?(s), do: fetch_initial_data(s), else: s
          end)
      end

    {:noreply, assign_sidebar_and_filter_assigns(socket)}
  end

  # ── handle_event ───────────────────────────────────────────────────────────

  def handle_event("filter_by_field", %{"field" => field, "id" => value}, socket)
      when is_binary(field) and is_binary(value) do
    filter_type = Client.api_key_to_filter_type(field)
    {:noreply, assign_sidebar_and_filter_assigns(toggle_filter(socket, filter_type, value))}
  end

  def handle_event("filter_by_" <> filter_type, %{"id" => value}, socket)
      when is_binary(filter_type) and is_binary(value) do
    {:noreply, assign_sidebar_and_filter_assigns(toggle_filter(socket, filter_type, value))}
  end

  def handle_event("load_more_search_results", _, socket) do
    if socket.assigns.has_more_items do
      {:noreply, assign_sidebar_and_filter_assigns(do_load_more(socket))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("load_more_" <> _filter_type, _, socket) do
    # Facets load in one request (`filter_group_fetch_limit`); kept for old cached JS.
    {:noreply, socket}
  end

  def handle_event("search", %{"term" => term}, socket) do
    {:noreply, assign_sidebar_and_filter_assigns(do_search(socket, term))}
  end

  def handle_event("clear_filters", _, socket) do
    {:noreply, assign_sidebar_and_filter_assigns(do_clear_filters(socket))}
  end

  def handle_event("clear_search", _, socket) do
    {:noreply, assign_sidebar_and_filter_assigns(do_clear_search(socket))}
  end

  def handle_event("remove_search_term", _, socket) do
    socket =
      socket
      |> assign(:term, nil)
      |> track_loading(:global_load, true)

    conditions = SearchLogic.build_search_conditions(socket.assigns)
    keys = SearchLogic.build_request_keys(socket.assigns[:filter_types])

    socket =
      case Client.find(
             conditions: conditions,
             range: [0, SearchLogic.default_per_page()],
             keys: keys,
             total: true,
             current_user: current_user(socket)
           ) do
        {:ok, %{items: items}} when is_list(items) ->
          {items_to_show, has_more} =
            SearchLogic.handle_pagination_results(items, SearchLogic.default_per_page())

          socket
          |> stream(:search_results, prepare_items(items_to_show), reset: true)
          |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
          |> update_available_filters(conditions)
          |> track_loading(:global_load, false)

        _ ->
          socket
          |> put_flash(:error, l("Error updating results"))
          |> track_loading(:global_load, false)
      end

    {:noreply, assign_sidebar_and_filter_assigns(socket)}
  end

  def handle_event("validate", _, socket), do: {:noreply, socket}

  # ── Private ────────────────────────────────────────────────────────────────

  @reserved_query_param_keys ~w(term vsn)

  defp stringify_query_params(params) when is_map(params) do
    Map.new(params, fn {k, v} -> {to_string(k), v} end)
  end

  defp normalize_term(t) when is_binary(t), do: String.trim(t)
  defp normalize_term(_), do: nil

  defp filters_from_query_params(qparams) when is_map(qparams) do
    qparams
    |> Enum.reject(fn {k, _} -> k in @reserved_query_param_keys end)
    |> Enum.reject(fn {_, v} -> query_value_empty?(v) end)
    |> Enum.flat_map(fn {k, v} ->
      filter_type = Client.api_key_to_filter_type(k)

      k
      |> query_values_list(v)
      |> Enum.map(fn val -> {filter_type, val} end)
    end)
    |> Enum.group_by(fn {t, _} -> t end, fn {_, v} -> v end)
    |> Map.new(fn {t, vals} -> {t, Enum.uniq(vals)} end)
  end

  defp query_values_list(_key, v) when is_list(v) do
    v
    |> Enum.flat_map(&List.wrap/1)
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp query_values_list(_key, v), do: query_values_list("ignored", List.wrap(v))

  defp query_value_empty?(nil), do: true
  defp query_value_empty?(v) when is_binary(v), do: String.trim(v) == ""
  defp query_value_empty?(v) when is_list(v), do: Enum.all?(v, &query_value_empty?/1)
  defp query_value_empty?(_), do: false

  defp apply_query_filters_search(socket) do
    socket =
      socket
      |> assign(:filter_types, SearchLogic.load_filter_types(current_user: current_user(socket)))
      |> track_loading(:global_load, true)

    conditions = SearchLogic.build_search_conditions(socket.assigns)
    keys = SearchLogic.build_request_keys(socket.assigns[:filter_types])

    case Client.find(
           conditions: conditions,
           range: [0, SearchLogic.default_per_page()],
           keys: keys,
           total: true,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items} = data} when is_list(items) ->
        {items_to_show, has_more} =
          SearchLogic.handle_pagination_results(items, SearchLogic.default_per_page())

        socket
        |> Bonfire.UI.Common.maybe_assign_context(data)
        |> stream(:search_results, prepare_items(items_to_show), reset: true)
        |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
        |> update_available_filters(conditions)
        |> track_loading(:global_load, false)

      _ ->
        socket
        |> assign_flash(:error, l("Error loading results"))
        |> track_loading(:global_load, false)
    end
  end

  defp assign_sidebar_and_filter_assigns(socket) do
    socket
    |> assign_filter_assigns()
    |> assign_sidebar_widgets()
    |> assign_pandora_urls()
  end

  defp assign_filter_assigns(socket) do
    logic = SearchLogic
    filter_types = socket.assigns[:filter_types] || logic.filter_types_fallback()
    available = socket.assigns[:available_filters] || %{}
    current = socket.assigns[:current_filters] || %{}
    pages = socket.assigns[:filter_pages] || %{}
    loading = socket.assigns[:filter_loading] || %{}

    filter_sections =
      logic.build_filter_sections(filter_types, available, current, pages, loading)

    active_filter_badges = logic.build_active_filter_badges(filter_types, current)
    selected_by_field = Map.new(filter_types, fn type -> {type, Map.get(current, type, [])} end)

    socket
    |> assign(:filter_sections, filter_sections)
    |> assign(:active_filter_badges, active_filter_badges)
    |> assign(:selected_by_field, selected_by_field)
  end

  defp assign_sidebar_widgets(socket) do
    filter_sections = socket.assigns[:filter_sections] || []
    loading = socket.assigns[:loading] || false

    widgets = [
      users: [
        secondary: [
          {Bonfire.PanDoRa.Web.WidgetSearchFiltersLive,
           [
             type: Surface.Component,
             filter_sections: filter_sections,
             loading: loading
           ]}
        ]
      ],
      guests: [
        secondary: [
          {Bonfire.PanDoRa.Web.WidgetSearchFiltersLive,
           [
             type: Surface.Component,
             filter_sections: filter_sections,
             loading: loading
           ]}
        ]
      ]
    ]

    assign(socket, :sidebar_widgets, widgets)
  end

  defp assign_pandora_urls(socket) do
    socket
    |> assign(:pandora_token, Auth.pandora_token(current_user: socket.assigns[:current_user]))
    |> assign(:pandora_base_url, String.trim_trailing(Client.get_pandora_url() || "", "/"))
  end

  defp data_loaded?(socket) do
    filter_types = socket.assigns[:filter_types] || []
    available = socket.assigns[:available_filters] || %{}
    length(filter_types) > 0 and map_size(available) > 0
  end

  defp fetch_initial_data(socket) do
    socket = track_loading(socket, :initial_load, true)

    socket =
      assign(
        socket,
        :filter_types,
        SearchLogic.load_filter_types(current_user: current_user(socket))
      )

    keys = SearchLogic.build_request_keys(socket.assigns[:filter_types])

    case Client.find(
           sort: [%{key: "title", operator: "+"}],
           range: [0, SearchLogic.default_per_page()],
           keys: keys,
           total: true,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items} = data} when is_list(items) ->
        {items_to_show, has_more} =
          SearchLogic.handle_pagination_results(items, SearchLogic.default_per_page())

        socket
        |> Bonfire.UI.Common.maybe_assign_context(data)
        |> stream(:search_results, prepare_items(items_to_show), reset: true)
        |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
        |> then(fn s ->
          case fetch_metadata(s, []) do
            {:ok, s2} -> s2
            {:error, s2} -> put_flash(s2, :error, l("Error loading filters"))
          end
        end)
        |> track_loading(:initial_load, false)

      _ ->
        socket
        |> track_loading(:initial_load, false)
        |> put_flash(:error, l("Error loading initial data"))
    end
  end

  defp do_initial_search(socket, term) do
    socket = track_loading(socket, :search_load, true)

    socket =
      assign(
        socket,
        :filter_types,
        SearchLogic.load_filter_types(current_user: current_user(socket))
      )

    conditions = SearchLogic.build_search_conditions(Map.merge(socket.assigns, %{term: term}))
    keys = SearchLogic.build_request_keys(socket.assigns[:filter_types])

    case Client.find(
           conditions: conditions,
           range: [0, SearchLogic.default_per_page()],
           keys: keys,
           total: true,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items} = data} when is_list(items) ->
        {items_to_show, has_more} =
          SearchLogic.handle_pagination_results(items, SearchLogic.default_per_page())

        socket
        |> Bonfire.UI.Common.maybe_assign_context(data)
        |> stream(:search_results, prepare_items(items_to_show), reset: true)
        |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
        |> track_loading(:search_load, false)
        |> then(fn s ->
          case fetch_metadata(s, conditions) do
            {:ok, s2} -> s2
            {:error, s2} -> put_flash(s2, :error, l("Error updating filters"))
          end
        end)

      _ ->
        socket
        |> assign(:error, l("Search failed"))
        |> track_loading(:search_load, false)
    end
  end

  defp do_search(socket, term) do
    socket =
      socket
      |> assign(term: term, current_filters: %{}, page: 0)
      |> track_loading(:search_load, true)

    conditions = [%{key: "*", operator: "=", value: term}]
    keys = SearchLogic.build_request_keys(socket.assigns[:filter_types])

    case Client.find(
           conditions: conditions,
           range: [0, SearchLogic.default_per_page()],
           keys: keys,
           total: true,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} =
          SearchLogic.handle_pagination_results(items, SearchLogic.default_per_page())

        socket
        |> stream(:search_results, prepare_items(items_to_show), reset: true)
        |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
        |> track_loading(:search_load, false)
        |> then(fn s ->
          case fetch_metadata(s, conditions) do
            {:ok, s2} -> s2
            {:error, s2} -> put_flash(s2, :error, l("Error updating filters"))
          end
        end)

      _ ->
        socket
        |> assign(:error, l("Search failed"))
        |> track_loading(:search_load, false)
    end
  end

  defp do_clear_filters(socket) do
    socket =
      socket
      |> assign(term: nil, current_filters: %{}, page: 0)
      |> stream(:search_results, [], reset: true)
      |> track_loading(:global_load, true)

    keys = SearchLogic.build_request_keys(socket.assigns[:filter_types])

    case Client.find(
           sort: [%{key: "title", operator: "+"}],
           range: [0, SearchLogic.default_per_page()],
           keys: keys,
           total: true,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} =
          SearchLogic.handle_pagination_results(items, SearchLogic.default_per_page())

        socket
        |> stream(:search_results, prepare_items(items_to_show))
        |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
        |> update_available_filters([])
        |> track_loading(:global_load, false)

      _ ->
        socket
        |> put_flash(:error, l("Error loading results"))
        |> track_loading(:global_load, false)
    end
  end

  defp do_clear_search(socket) do
    socket
    |> assign(
      term: nil,
      current_filters: %{},
      page: 0,
      filter_sections: [],
      active_filter_badges: [],
      selected_by_field: %{}
    )
    |> stream(:search_results, [], reset: true)
    |> assign(:filter_types, SearchLogic.load_filter_types(current_user: current_user(socket)))
    |> fetch_initial_data()
  end

  defp filter_value_matches?(v, value) when is_binary(value) do
    v == value or to_string(v) == value
  end

  defp toggle_filter(socket, filter_type, value)
       when is_binary(filter_type) and is_binary(value) do
    current = socket.assigns[:current_filters] || %{}
    values = Map.get(current, filter_type, [])

    updated_values =
      if Enum.any?(values, &filter_value_matches?(&1, value)) do
        Enum.reject(values, &filter_value_matches?(&1, value))
      else
        [value | values]
      end

    new_filters = Map.put(current, filter_type, updated_values)
    socket = socket |> assign(:current_filters, new_filters) |> track_loading(:global_load, true)

    conditions =
      SearchLogic.build_search_conditions(
        Map.merge(socket.assigns, %{current_filters: new_filters})
      )

    keys = SearchLogic.build_request_keys(socket.assigns[:filter_types])

    case Client.find(
           conditions: conditions,
           range: [0, SearchLogic.default_per_page()],
           keys: keys,
           total: true,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} =
          SearchLogic.handle_pagination_results(items, SearchLogic.default_per_page())

        socket
        |> stream(:search_results, prepare_items(items_to_show), reset: true)
        |> assign(has_more_items: has_more, current_count: length(items_to_show), page: 0)
        |> update_available_filters(conditions)
        |> track_loading(:global_load, false)

      _ ->
        socket
        |> assign(:current_filters, current)
        |> put_flash(:error, l("Error updating results"))
        |> track_loading(:global_load, false)
    end
  end

  defp do_load_more(socket) do
    socket = track_loading(socket, :more_load, true)
    next_page = socket.assigns.page + 1
    conditions = SearchLogic.build_search_conditions(socket.assigns)
    start = next_page * SearchLogic.default_per_page()
    keys = SearchLogic.build_request_keys(socket.assigns[:filter_types])

    case Client.find(
           conditions: conditions,
           range: [start, start + SearchLogic.default_per_page()],
           keys: keys,
           current_user: current_user(socket)
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {items_to_show, has_more} =
          SearchLogic.handle_pagination_results(items, SearchLogic.default_per_page())

        socket
        |> stream(:search_results, prepare_items(items_to_show))
        |> assign(
          page: next_page,
          has_more_items: has_more,
          current_count: socket.assigns.current_count + length(items_to_show)
        )
        |> track_loading(:more_load, false)
        |> track_loading(:global_load, false)

      _ ->
        socket
        |> assign(:error, l("Failed to load more"))
        |> track_loading(:more_load, false)
        |> track_loading(:global_load, false)
    end
  end

  defp fetch_metadata(socket, conditions) do
    socket = track_loading(socket, :metadata_load, true)
    filter_types = socket.assigns[:filter_types] || SearchLogic.filter_types_fallback()

    case Client.fetch_grouped_metadata(conditions,
           fields: filter_types,
           per_page: SearchLogic.filter_group_fetch_limit(),
           page: 0,
           current_user: current_user(socket)
         ) do
      {:ok, %{filters: filters, api_keys: api_keys}} ->
        available =
          Enum.reduce(filter_types, %{}, fn type, acc ->
            Map.put(acc, type, Map.get(filters, type, []))
          end)

        filter_has_more = Map.new(filter_types, fn type -> {type, false} end)

        {:ok,
         socket
         |> assign(:available_filters, available)
         |> assign(:effective_api_keys, api_keys)
         |> assign(:filter_has_more, filter_has_more)
         |> track_loading(:metadata_load, false)}

      {:error, _} ->
        {:error, socket |> track_loading(:metadata_load, false)}
    end
  end

  defp update_available_filters(socket, conditions) do
    filter_types = socket.assigns[:filter_types] || SearchLogic.filter_types_fallback()

    case Client.fetch_grouped_metadata(conditions,
           fields: filter_types,
           per_page: SearchLogic.filter_group_fetch_limit(),
           page: 0,
           current_user: current_user(socket)
         ) do
      {:ok, %{filters: filters, api_keys: api_keys}} ->
        new_available =
          Enum.reduce(filter_types, %{}, fn type, acc ->
            Map.put(acc, type, Map.get(filters, type, []))
          end)

        socket
        |> assign(:available_filters, new_available)
        |> assign(:filter_has_more, Map.new(filter_types, fn t -> {t, false} end))
        |> assign(
          :effective_api_keys,
          Map.merge(socket.assigns[:effective_api_keys] || %{}, api_keys)
        )

      _ ->
        put_flash(socket, :error, l("Error updating filters"))
    end
  end

  defp track_loading(socket, state, is_loading) do
    current = Map.get(socket.assigns, :loading_states, MapSet.new())

    new_loading =
      if is_loading, do: MapSet.put(current, state), else: MapSet.delete(current, state)

    socket
    |> assign(:loading_states, new_loading)
    |> assign(:loading, MapSet.size(new_loading) > 0)
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
