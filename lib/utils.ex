defmodule Bonfire.PanDoRa.Utils do
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
