defmodule Bonfire.PanDoRa.Utils do
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
