defmodule Bonfire.PanDoRa.Web.WidgetMovieInfoLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Utils

  defdelegate to_attr(v), to: Utils
  defdelegate extra_metadata(movie), to: Utils

  prop links, :any, default: []
  prop widget_title, :string, default: nil
  prop movie, :any, default: nil

  def mount(socket) do
    {:ok, assign(socket, :show_more, false)}
  end

  def handle_event("toggle_more", _params, socket) do
    {:noreply, update(socket, :show_more, &(!&1))}
  end

  @doc "True if movie has non-empty summary to display."
  def summary_present?(nil), do: false
  def summary_present?(movie) when is_map(movie) do
    case movie["summary"] do
      s when is_binary(s) and byte_size(s) > 0 -> true
      _ -> false
    end
  end
  def summary_present?(_), do: false

  def is_long_summary?(movie) do
    summary = e(movie, "summary", "")
    String.length(summary) >= 240
  end

  def get_summary(movie, show_all \\ false) do
    summary = e(movie, "summary", "")

    if show_all || !is_long_summary?(movie) do
      summary
    else
      String.slice(summary, 0, 240) <> "..."
    end
  end

  @doc "Saturation for HUE swatch (0-100), default 50."
  def hue_saturation(movie) when is_map(movie) do
    case movie["saturation"] do
      n when is_number(n) -> min(100, max(0, trunc(n)))
      s when is_binary(s) -> case Float.parse(s) do
        {n, _} -> min(100, max(0, trunc(n)))
        :error -> 50
      end
      _ -> 50
    end
  end
  def hue_saturation(_), do: 50

  @doc "Lightness for HUE swatch (0-100), default 50."
  def hue_lightness(movie) when is_map(movie) do
    case movie["lightness"] do
      n when is_number(n) -> min(100, max(0, trunc(n)))
      s when is_binary(s) -> case Float.parse(s) do
        {n, _} -> min(100, max(0, trunc(n)))
        :error -> 50
      end
      _ -> 50
    end
  end
  def hue_lightness(_), do: 50

  @doc "Rounds a number to 2 decimal places for display."
  def format_decimal(nil), do: ""
  def format_decimal(n) when is_number(n), do: :erlang.float_to_binary(Float.round(n, 2), [decimals: 2])
  def format_decimal(s) when is_binary(s) do
    case Float.parse(s) do
      {n, _} -> format_decimal(n)
      :error -> s
    end
  end
  def format_decimal(v), do: to_string(v)

  @doc "Aspect ratio from API (aspectRatio, aspect_ratio, ratio)."
  def api_aspect_ratio(movie) when is_map(movie) do
    movie["aspectRatio"] || movie["aspect_ratio"] || movie["ratio"]
  end
  def api_aspect_ratio(_), do: nil

  @doc "Duration from API: uses 'duration' or falls back to 'runtime'."
  def api_duration(movie) when is_map(movie) do
    movie["duration"] || movie["runtime"]
  end
  def api_duration(_), do: nil

  @doc "Formats API duration (seconds number or pre-formatted string) to M:SS or H:MM:SS."
  def format_duration_seconds(nil), do: "0:00"
  def format_duration_seconds(sec) when is_number(sec) do
    sec = trunc(Float.ceil(sec))
    h = div(sec, 3600)
    m = rem(div(sec, 60), 60)
    s = rem(sec, 60)
    if h > 0 do
      "#{h}:#{pad(m)}:#{pad(s)}"
    else
      "#{m}:#{pad(s)}"
    end
  end
  def format_duration_seconds(s) when is_binary(s) and s != "", do: s
  def format_duration_seconds(_), do: "0:00"

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: to_string(n)

  @doc "Returns director(s) as a list of strings for button rendering."
  def director_list(movie) when is_map(movie) do
    case movie["director"] do
      list when is_list(list) -> Enum.filter(list, &is_binary/1)
      s when is_binary(s) and s != "" ->
        s |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
      _ -> []
    end
  end
  def director_list(_), do: []

  @doc "Returns featuring as a list of strings for badge rendering."
  def featuring_list(movie) when is_map(movie) do
    case movie["featuring"] do
      list when is_list(list) -> Enum.filter(list, &is_binary/1)
      s when is_binary(s) and s != "" ->
        s |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
      _ -> []
    end
  end

  def featuring_list(_), do: []
end
