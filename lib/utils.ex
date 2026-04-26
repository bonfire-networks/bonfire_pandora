defmodule Bonfire.PanDoRa.Utils do
  alias PanDoRa.API.Client

  @doc """
  Converts any Pandora field value to a safe string for HTML attributes.
  Nil becomes "", lists are joined (binaries only), maps become "" (avoid `to_string` on maps).
  """
  def to_attr(nil), do: ""
  def to_attr(list) when is_list(list), do: list |> Enum.filter(&is_binary/1) |> Enum.join(", ")
  def to_attr(m) when is_map(m), do: ""
  def to_attr(v), do: to_string(v)

  @doc """
  Path-like Pandora titles often have no spaces, so the browser does not wrap them.

  Inserts U+200B (zero-width space) after `/`, `_`, and `-` so lines can break at those
  characters. Still combine with CSS `break-all` on the container for segments that remain
  a single long token (e.g. a trailing id).

  ## Examples

      iex> Bonfire.PanDoRa.Utils.insert_line_break_hints("a/b_c-d")
      "a/\u200Bb_\u200Bc-\u200Bd"

      iex> Bonfire.PanDoRa.Utils.insert_line_break_hints("")
      ""

  """
  def insert_line_break_hints(title) when is_binary(title) and title != "" do
    title
    |> String.replace("/", "/\u200B")
    |> String.replace("_", "_\u200B")
    |> String.replace("-", "-\u200B")
  end

  def insert_line_break_hints(_), do: ""

  @doc """
  Inline CSS for a timeline-strip marker positioned over the antialias frame
  preview. Computes `left%` and `width%` from the annotation `in`/`out`
  timestamps (seconds) against the movie `duration` (seconds).

  Returns `""` when `duration` is missing/non-positive or when the timestamps
  are unusable, so the template can render the element without polluting the
  layout.

  ## Examples

      iex> Bonfire.PanDoRa.Utils.timeline_marker_style(%{"in" => 30, "out" => 60}, 300)
      "left: 10.0%; width: 10.0%;"

      iex> Bonfire.PanDoRa.Utils.timeline_marker_style(%{"in" => 30, "out" => 60}, 0)
      ""
  """
  def timeline_marker_style(note, duration)
      when is_map(note) and is_number(duration) and duration > 0 do
    with {:ok, t_in} <- timeline_marker_seconds(note["in"]),
         {:ok, t_out} <- timeline_marker_seconds(note["out"]),
         t_out when t_out > t_in <- t_out do
      left_pct = clamp_pct(t_in / duration * 100)
      width_pct = clamp_pct((t_out - t_in) / duration * 100)
      "left: #{format_pct(left_pct)}%; width: #{format_pct(width_pct)}%;"
    else
      _ -> ""
    end
  end

  def timeline_marker_style(_, _), do: ""

  defp timeline_marker_seconds(n) when is_number(n) and n >= 0, do: {:ok, n * 1.0}

  defp timeline_marker_seconds(s) when is_binary(s) do
    case Float.parse(String.trim(s)) do
      {n, _} when n >= 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp timeline_marker_seconds(_), do: :error

  defp clamp_pct(p) when p < 0, do: 0.0
  defp clamp_pct(p) when p > 100, do: 100.0
  defp clamp_pct(p), do: p * 1.0

  # 2 decimals is enough for sub-pixel precision on a 16p strip rescaled to ~40px.
  defp format_pct(p), do: :erlang.float_to_binary(p, decimals: 2)

  @doc """
  Structural/technical fields handled explicitly in templates.
  Instance-specific keys (sezione, edizione, genre, etc.) are intentionally excluded
  so they appear dynamically via extra_metadata/1.
  """
  @known_fields ~w(id title item_id public_id stable_id order duration director image
                   year summary hue saturation lightness volume cutsperminute rightslevel stream
                   streams bitrate editable featuring country language keywords keyword
                   aspectRatio aspect_ratio ratio resolution keywordLayerAnnotations runtime
                   keywordFacetNames)

  def known_fields, do: @known_fields

  # Pandora item payloads include many technical keys; hide them from the movie widget “extra” list.
  @extra_metadata_suppress MapSet.new(
                             ~w(
      videoratio posterratio numberofcuts rendered size numberoffiles posterframe pixels
      created parts aspectratio random modified user mimetype codec framerate fps
      width height filesize filesizebytes filepath filename bitratekbps durationms
      durationframe startframe endframe md5 sha checksum hash uuid revision version
      imported exported indexed transcoded proxy thumbnail thumb posteruri streamuri
      itemtype mediatype container format profile level rotation flip mirror cuts cutlist
    ),
                             &String.downcase/1
                           )

  defp known_movie_field?(k), do: to_string(k) in @known_fields

  defp extra_metadata_suppressed?(k),
    do: MapSet.member?(@extra_metadata_suppress, String.downcase(to_string(k)))

  @doc "Returns extra metadata fields (not in known_fields) with non-empty values."
  def extra_metadata(movie) when is_map(movie) do
    movie
    |> Enum.reject(fn {k, v} ->
      known_movie_field?(k) or extra_metadata_suppressed?(k) or is_nil(v) or v == "" or v == [] or
        is_map(v)
    end)
    |> Enum.map(fn {k, v} -> {k, to_attr(v)} end)
    |> Enum.reject(fn {_k, v} -> v == "" end)
  end

  def extra_metadata(_), do: []

  @doc """
  Like `extra_metadata/1` but omits keys that are already rendered as archive filter facets
  (same types as the Filters widget).
  """
  def extra_metadata_excluding_filters(movie, filter_types, effective_api_keys) when is_map(movie) do
    exclude =
      (filter_types || [])
      |> Enum.flat_map(fn t ->
        ak = Map.get(effective_api_keys || %{}, t) || Client.filter_type_to_api_key(t)
        [String.downcase(to_string(ak)), String.downcase(to_string(t))]
      end)
      |> MapSet.new()

    movie
    |> extra_metadata()
    |> Enum.reject(fn {k, _v} -> MapSet.member?(exclude, String.downcase(to_string(k))) end)
  end

  def extra_metadata_excluding_filters(_, _, _), do: []

  @doc "Iconify icon name for a filter type (archive card facet row)."
  def filter_field_icon("year"), do: "carbon:calendar"
  def filter_field_icon("featuring"), do: "carbon:user-multiple"
  def filter_field_icon("keywords"), do: "carbon:tag"
  def filter_field_icon("keyword"), do: "carbon:tag"
  def filter_field_icon(_), do: "carbon:information"

  @facet_btn_base "btn btn-xs btn-soft h-auto min-h-7 py-0.5 px-1.5 gap-1 font-normal max-w-[min(100%,14rem)]"

  @doc "DaisyUI button classes for a facet chip (archive card, filter links on)."
  def filter_field_button_class(type) when is_binary(type) do
    variant = type |> normalize_filter_type() |> facet_btn_variant()
    "#{@facet_btn_base} #{variant}"
  end

  def filter_field_button_class(_), do: "#{@facet_btn_base} btn-neutral"

  @doc "DaisyUI badge classes for a facet chip (archive card, filter links off)."
  def filter_field_badge_class(type) when is_binary(type) do
    variant = type |> normalize_filter_type() |> facet_badge_variant()
    "badge badge-sm #{variant} gap-1 max-w-[min(100%,14rem)]"
  end

  def filter_field_badge_class(_), do: "badge badge-sm badge-ghost gap-1 max-w-[min(100%,14rem)]"

  @doc "Tailwind classes for the Iconify glyph on a facet row (semantic tint)."
  def filter_field_icon_class(type) when is_binary(type) do
    type |> normalize_filter_type() |> facet_icon_class()
  end

  def filter_field_icon_class(_), do: "w-3.5 h-3.5 shrink-0 opacity-90"

  defp normalize_filter_type("keyword"), do: "keywords"
  defp normalize_filter_type(t), do: t

  defp facet_btn_variant("featuring"), do: "btn-success"
  defp facet_btn_variant("keywords"), do: "btn-accent"
  defp facet_btn_variant(_), do: "btn-neutral"

  defp facet_badge_variant("featuring"), do: "badge-success"
  defp facet_badge_variant("keywords"), do: "badge-accent"
  defp facet_badge_variant(_), do: "badge-ghost"

  defp facet_icon_class("featuring"), do: "w-3.5 h-3.5 shrink-0 opacity-95 text-success-content"
  defp facet_icon_class("keywords"), do: "w-3.5 h-3.5 shrink-0 opacity-95 text-accent-content"
  defp facet_icon_class(_), do: "w-3.5 h-3.5 shrink-0 opacity-90 text-current"

  @card_facet_skip ~w(director country language year)

  @doc """
  Country values for the archive card header row (template uses inline SVG globe, not Iconify).
  Country is not included in `filter_facets_for_card/3`.
  """
  def country_facets_for_card(movie, filter_types, effective_api_keys) when is_map(movie) do
    if "country" in List.wrap(filter_types) do
      api_key = Map.get(effective_api_keys || %{}, "country") || Client.filter_type_to_api_key("country")
      raw = Map.get(movie, api_key) || Map.get(movie, "country")

      raw
      |> normalize_facet_values()
      |> Enum.map(fn val -> %{api_key: api_key, value: val} end)
    else
      []
    end
  end

  def country_facets_for_card(_, _, _), do: []

  @doc """
  Year values for the archive card header row (with title); not included in `filter_facets_for_card/3`.
  """
  def year_facets_for_card(movie, filter_types, effective_api_keys) when is_map(movie) do
    if "year" in List.wrap(filter_types) do
      api_key = Map.get(effective_api_keys || %{}, "year") || Client.filter_type_to_api_key("year")
      raw = Map.get(movie, api_key) || Map.get(movie, "year")

      raw
      |> normalize_facet_values()
      |> Enum.map(fn val -> %{api_key: api_key, value: val} end)
    else
      []
    end
  end

  def year_facets_for_card(_, _, _), do: []

  @doc """
  Builds one row entry per facet value for filter types (excluding director, country, language, year).
  Uses `effective_api_keys` from grouped-metadata so `keyword`/`keywords` matches the API.
  """
  def filter_facets_for_card(movie, filter_types, effective_api_keys) when is_map(movie) do
    filter_types
    |> List.wrap()
    |> Enum.reject(&(&1 in @card_facet_skip))
    |> Enum.flat_map(fn type ->
      api_key = Map.get(effective_api_keys || %{}, type) || Client.filter_type_to_api_key(type)
      raw = Map.get(movie, api_key) || Map.get(movie, type)
      icon = filter_field_icon(type)

      raw
      |> normalize_facet_values()
      |> Enum.map(fn val ->
        %{
          type: type,
          api_key: api_key,
          value: val,
          icon: icon,
          button_class: filter_field_button_class(type),
          badge_class: filter_field_badge_class(type),
          icon_class: filter_field_icon_class(type)
        }
      end)
    end)
  end

  def filter_facets_for_card(_, _, _), do: []

  defp normalize_facet_values(nil), do: []
  defp normalize_facet_values(v) when v == "", do: []
  defp normalize_facet_values(v) when is_integer(v), do: [Integer.to_string(v)]

  defp normalize_facet_values(v) when is_binary(v) do
    t = String.trim(v)
    if t == "", do: [], else: [t]
  end

  defp normalize_facet_values(v) when is_list(v) do
    Enum.flat_map(v, &normalize_facet_values/1)
  end

  defp normalize_facet_values(_), do: []

  def sort_years(years) do
    Enum.sort_by(years, fn %{"name" => year} ->
      case Integer.parse(year) do
        {num, _} -> -num
        _ -> 0
      end
    end)
  end

  def generate_stable_id(item) do
    # Ensure we have all parts for a unique ID
    director = Map.get(item, "director", [])

    director_string =
      cond do
        is_list(director) -> Enum.join(director, "-")
        is_binary(director) -> director
        true -> ""
      end

    [
      Map.get(item, "title", ""),
      director_string,
      Map.get(item, "year", ""),
      # Add something unique for the same item in different pages
      Map.get(item, "id", "") || Ecto.UUID.generate()
    ]
    |> Enum.join("-")
    |> :erlang.phash2()
    |> to_string()
  end
end
