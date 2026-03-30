defmodule Bonfire.PanDoRa.Components.MoviePreviewLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Utils

  prop movie_id, :string, required: true

  # nil when used inside a LiveView (events routed to LV); pass @myself when inside a LiveComponent
  prop event_target, :any, default: nil
  prop movie, :map, required: true
  prop image_src, :string, default: nil
  prop media_url, :string, default: nil
  prop filter_types, :list, default: []
  prop effective_api_keys, :map, default: %{}
  prop filter_links_enabled, :boolean, default: true

  defdelegate to_attr(v), to: Bonfire.PanDoRa.Utils
  defdelegate extra_metadata(movie), to: Bonfire.PanDoRa.Utils
  defdelegate extra_metadata_excluding_filters(movie, filter_types, effective_api_keys),
    to: Bonfire.PanDoRa.Utils

  defdelegate filter_facets_for_card(movie, filter_types, effective_api_keys),
    to: Bonfire.PanDoRa.Utils

  defdelegate country_facets_for_card(movie, filter_types, effective_api_keys),
    to: Bonfire.PanDoRa.Utils

  defdelegate year_facets_for_card(movie, filter_types, effective_api_keys),
    to: Bonfire.PanDoRa.Utils

  defdelegate insert_line_break_hints(title), to: Bonfire.PanDoRa.Utils

  @doc "Trimmed item summary for description block; nil if absent."
  def summary_text(movie) when is_map(movie) do
    case Map.get(movie, "summary") do
      s when is_binary(s) ->
        t = String.trim(s)
        if t == "", do: nil, else: t

      _ ->
        nil
    end
  end

  def summary_text(_), do: nil
end
