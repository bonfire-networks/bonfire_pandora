defmodule Bonfire.PanDoRa.Web.SearchLogic do
  @moduledoc """
  Pure logic for archive search: conditions, keys, filter sections.
  Used by SearchViewLive.
  """
  alias PanDoRa.API.Client

  @filter_types_fallback ~w(director featuring language country year keywords)
  @essential_keys ~w(title id item_id public_id duration summary)
  @default_per_page 20

  def filter_types_fallback, do: @filter_types_fallback
  def default_per_page, do: @default_per_page

  @doc "Max facet buckets per archive filter request (see `PanDoRa.API.Client.fetch_grouped_metadata/2`)."
  def filter_group_fetch_limit, do: Client.default_grouped_metadata_per_page()

  def load_filter_types(opts) do
    filter_types = Client.get_filter_keys(opts)

    if is_list(filter_types) and filter_types != [],
      do: filter_types,
      else: @filter_types_fallback
  end

  def build_request_keys(filter_types) do
    api_keys = Enum.map(filter_types, &Client.filter_type_to_api_key/1)
    (@essential_keys ++ api_keys) |> Enum.uniq()
  end

  def build_search_conditions(%{
        term: term,
        current_filters: current_filters,
        effective_api_keys: effective_api_keys
      }) do
    filter_conditions =
      (current_filters || %{})
      |> Enum.flat_map(fn {type, values} ->
        api_key = Map.get(effective_api_keys || %{}, type) || Client.filter_type_to_api_key(type)

        case values do
          [] ->
            []

          [single] ->
            [normalize_condition_value(api_key, single, type)]

          multiple ->
            [
              %{
                conditions: Enum.map(multiple, &normalize_condition_value(api_key, &1, type)),
                operator: "|"
              }
            ]
        end
      end)

    case {term, filter_conditions} do
      {nil, []} ->
        []

      {t, []} when is_binary(t) and t != "" ->
        [%{key: "*", operator: "=", value: t}]

      {nil, [single]} ->
        [single]

      {nil, multiple} when multiple != [] ->
        multiple

      {t, filters} when is_binary(t) and t != "" ->
        [%{key: "*", operator: "=", value: t} | filters]
    end
  end

  def build_search_conditions(assigns) when is_map(assigns) do
    build_search_conditions(%{
      term: Map.get(assigns, :term),
      current_filters: Map.get(assigns, :current_filters, %{}),
      effective_api_keys: Map.get(assigns, :effective_api_keys, %{})
    })
  end

  defp normalize_condition_value(api_key, value, "year") when is_binary(value) do
    op = Client.operator_for_filter_type("year")
    %{key: api_key, operator: op, value: value}
  end

  defp normalize_condition_value(api_key, value, "year") when is_integer(value) do
    op = Client.operator_for_filter_type("year")
    %{key: api_key, operator: op, value: to_string(value)}
  end

  defp normalize_condition_value(api_key, value, type) do
    op = Client.operator_for_filter_type(type)
    %{key: api_key, operator: op, value: value}
  end

  def build_filter_sections(
        filter_types,
        available_filters,
        current_filters,
        filter_pages,
        filter_loading
      ) do
    Enum.map(filter_types, fn type ->
      list = Map.get(available_filters, type, [])

      available =
        Enum.map(list, fn
          %{"name" => n, "items" => c} ->
            %{name: to_string(n), items: c}

          %{name: n, items: c} ->
            %{name: to_string(n), items: c}

          %{} = other ->
            %{
              name: to_string(Map.get(other, "name") || Map.get(other, :name) || "Unknown"),
              items: Map.get(other, "items") || Map.get(other, :items) || 0
            }

          other ->
            %{name: to_string(other), items: 0}
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
  end

  def build_active_filter_badges(filter_types, current_filters) do
    Enum.map(filter_types, fn type ->
      values = Map.get(current_filters, type, [])
      label = Gettext.gettext(Bonfire.Common.Localise.Gettext, String.capitalize(type))
      %{id: type, label: label, values: values}
    end)
  end

  def handle_pagination_results(items, per_page) when is_list(items) do
    if length(items) > per_page,
      do: {Enum.take(items, per_page), true},
      else: {items, false}
  end
end
