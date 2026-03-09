defmodule Bonfire.PanDoRa.Utils do
  @doc """
  Converts any Pandora field value to a safe string for HTML attributes.
  Nil becomes "", lists are joined, anything else is to_string'd.
  """
  def to_attr(nil), do: ""
  def to_attr(list) when is_list(list), do: list |> Enum.filter(&is_binary/1) |> Enum.join(", ")
  def to_attr(v), do: to_string(v)

  @doc """
  Structural/technical fields handled explicitly in templates.
  Instance-specific keys (sezione, edizione, genre, etc.) are intentionally excluded
  so they appear dynamically via extra_metadata/1.
  """
  @known_fields ~w(id title item_id public_id stable_id order duration director image
                   year summary hue saturation lightness volume cutsperminute rights stream)

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
