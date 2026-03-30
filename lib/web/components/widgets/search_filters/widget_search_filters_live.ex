defmodule Bonfire.PanDoRa.Web.WidgetSearchFiltersLive do
  @moduledoc """
  Sidebar widget for archive search filters (director, year, keywords, etc.).
  Renders filter blocks; events bubble to the parent LiveView (SearchViewLive).

  UI is tunable via `Bonfire.Common.Settings` under `[:ui, :archive_search_filters, …]`,
  same pattern as `Bonfire.Tag.Web.WidgetTagsLive` (trending topics).
  """
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Localise

  prop filter_sections, :list, default: []
  prop loading, :boolean, default: false
  prop widget_title, :string, default: nil

  @doc "True when instance settings hide this widget."
  def filters_disabled?(context) do
    Bonfire.Common.Settings.get([:ui, :archive_search_filters, :disabled], nil,
      context: context,
      name: l("Hide archive search filters"),
      description:
        l("When enabled, the sidebar filters block is hidden on the archive search page.")
    ) == true
  end

  @doc "Sidebar title: prop wins, then instance setting, then default."
  def filters_widget_title(prop_title, context) do
    setting =
      Bonfire.Common.Settings.get([:ui, :archive_search_filters, :widget_title], nil,
        context: context,
        name: l("Archive filters widget title"),
        description: l("Custom title for the archive filters sidebar block.")
      )

    cond do
      is_binary(prop_title) and String.trim(prop_title) != "" ->
        String.trim(prop_title)

      is_binary(setting) and String.trim(setting) != "" ->
        String.trim(setting)

      true ->
        l("Filters")
    end
  end

  @doc "Pixel height of each facet list scroll area."
  def filters_list_height_px(context) do
    raw =
      Bonfire.Common.Settings.get([:ui, :archive_search_filters, :list_height_px], 140,
        context: context,
        name: l("Archive filters list height"),
        description: l("Height in pixels of the scrollable facet list for each filter field.")
      )

    n =
      cond do
        is_integer(raw) and raw > 0 ->
          raw

        is_binary(raw) ->
          case Integer.parse(String.trim(raw)) do
            {i, _} when i > 0 -> i
            _ -> 140
          end

        true ->
          140
      end

    min(n, 2000)
  end

  @doc """
  Title style: \"compact\" (small uppercase) or \"prominent\" (large bold, like Trending topics).
  """
  def filters_title_class(context) do
    raw =
      Bonfire.Common.Settings.get([:ui, :archive_search_filters, :title_style], "compact",
        context: context,
        name: l("Archive filters title style"),
        description:
          l("compact: small uppercase; prominent: large bold like other sidebar widgets.")
      )

    case normalize_archive_style_value(raw) do
      "prominent" ->
        "flex gap-3 text-base-content/90 pb-2 text-lg font-bold tracking-wide"

      _ ->
        "text-xs font-medium uppercase tracking-wider text-base-content/40 pb-2"
    end
  end

  @doc """
  Outer block: \"transparent\" (flush) or \"card\" (default WidgetBlockLive card padding).
  """
  def filters_block_class(context) do
    raw =
      Bonfire.Common.Settings.get([:ui, :archive_search_filters, :card_style], "transparent",
        context: context,
        name: l("Archive filters card style"),
        description: l("transparent: flush sidebar; card: padded card like other widgets.")
      )

    case normalize_archive_style_value(raw) do
      "card" ->
        "w-full p-4 flex-auto mx-auto bonfire-wrapper"

      _ ->
        "w-full p-0 border-0 bg-transparent shadow-none"
    end
  end

  # Instance settings often round-trip as atoms (:prominent) or mixed case; UI only uses lowercase strings.
  defp normalize_archive_style_value(v) do
    cond do
      is_nil(v) ->
        ""

      is_atom(v) ->
        v |> Atom.to_string() |> String.trim() |> String.downcase()

      is_binary(v) ->
        v |> String.trim() |> String.downcase()

      true ->
        ""
    end
  end

  @doc "Inline style for the facet `<ul>` scroll region."
  def filters_list_style(context) do
    h = filters_list_height_px(context)
    "min-height:0;height:#{h}px;max-height:#{h}px"
  end
end
