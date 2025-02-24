# lib/pandora/archives.ex
defmodule Bonfire.PanDoRa.Archives do
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.PaginationContext

  @default_per_page 20
  @filter_per_page 10
  @default_keys ~w(title id item_id public_id director sezione edizione featuring duration)

  def search_items(conditions, opts \\ []) do
    page = Keyword.get(opts, :page, 0)
    per_page = Keyword.get(opts, :per_page, @default_per_page)

    Client.find(
      conditions: conditions,
      range: [page * per_page, per_page],
      keys: @default_keys,
      total: true
    )
  end

  def fetch_metadata(conditions, opts \\ []) do
    field = Keyword.get(opts, :field)
    page = Keyword.get(opts, :page, 0)
    per_page = Keyword.get(opts, :per_page, @filter_per_page)

    client_opts = [per_page: per_page]
    client_opts = if field, do: [{:field, field}, {:page, page} | client_opts], else: client_opts

    Client.fetch_grouped_metadata(conditions, client_opts)
  end

  def build_search_query(term, filters) do
    filter_conditions = build_filter_conditions(filters)

    case {term, filter_conditions} do
      {nil, []} -> []
      {term, []} when is_binary(term) and term != "" ->
        [%{key: "*", operator: "=", value: term}]
      {nil, [single]} -> [single]
      {nil, multiple} when length(multiple) > 0 ->
        [%{conditions: multiple, operator: "&"}]
      {term, filters} when is_binary(term) and term != "" ->
        [%{conditions: [%{key: "*", operator: "=", value: term} | filters], operator: "&"}]
    end
  end

  defp build_filter_conditions(filters) do
    filters
    |> Enum.reject(fn {_type, values} -> values == [] end)
    |> Enum.map(fn
      {type, [value]} -> %{key: type, operator: "==", value: value}
      {type, values} when length(values) > 0 ->
        %{
          conditions: Enum.map(values, &%{key: type, operator: "==", value: &1}),
          operator: "|"
        }
    end)
  end
end
