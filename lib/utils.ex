defmodule Bonfire.PanDoRa.Utils do
  @doc """
  Converts any Pandora field value to a safe string for HTML attributes.
  Nil becomes "", lists are joined, anything else is to_string'd.
  """
  def to_attr(nil), do: ""
  def to_attr(list) when is_list(list), do: list |> Enum.filter(&is_binary/1) |> Enum.join(", ")
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
                   aspectRatio aspect_ratio ratio resolution)

  def known_fields, do: @known_fields

  @doc "Returns extra metadata fields (not in known_fields) with non-empty values."
  def extra_metadata(movie) when is_map(movie) do
    movie
    |> Enum.reject(fn {k, v} -> k in @known_fields or is_nil(v) or v == "" or v == [] end)
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
