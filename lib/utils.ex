defmodule Bonfire.PanDoRa.Utils do
  def format_duration(duration) when is_binary(duration) do
    case Float.parse(duration) do
      {seconds, _} -> format_duration(seconds)
      :error -> duration
    end
  end

  def format_duration(seconds) when is_float(seconds) do
    total_minutes = trunc(seconds / 60)
    hours = div(total_minutes, 60)
    minutes = rem(total_minutes, 60)
    remaining_seconds = seconds - (total_minutes * 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}min"
      minutes > 0 -> "#{minutes}min"
      true -> "#{Float.round(remaining_seconds, 2)}s"
    end
  end

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
    director_string = cond do
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
