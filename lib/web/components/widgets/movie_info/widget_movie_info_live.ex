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
    {:ok,
     socket
     |> assign(:show_more, false)
     |> assign(:keywords_form, to_form(%{keywords: []}, as: :movie))
     |> assign(:kw_form_digest, nil)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    movie = socket.assigns[:movie]
    kws = if movie, do: keywords_list(movie), else: []
    digest = keywords_form_digest(movie, kws)

    socket =
      if digest != socket.assigns[:kw_form_digest] do
        socket
        |> assign(:kw_form_digest, digest)
        |> assign(:keywords_form, to_form(%{keywords: kws}, as: :movie))
      else
        socket
      end

    {:ok, socket}
  end

  def handle_event("toggle_more", _params, socket) do
    {:noreply, update(socket, :show_more, &(!&1))}
  end

  def handle_event("live_select_change", %{"id" => live_select_id, "text" => text}, socket)
      when is_binary(text) do
    q = String.trim(text)

    if q == "" do
      maybe_send_update(LiveSelect.Component, live_select_id, options: [])
      {:noreply, socket}
    else
      down = String.downcase(q)
      opts = [field: "keywords", per_page: 50, current_user: current_user(socket)]

      case Client.fetch_grouped_metadata([], opts) do
        {:ok, %{filters: filters}} ->
          names =
            filters
            |> Map.get("keywords", [])
            |> Enum.map(&metadata_keyword_name/1)
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

          matching =
            names
            |> Enum.filter(fn name ->
              String.contains?(String.downcase(name), down)
            end)
            |> Enum.take(30)

          options = Enum.map(matching, fn name -> {name, name} end)
          maybe_send_update(LiveSelect.Component, live_select_id, options: options)
          {:noreply, socket}

        _ ->
          maybe_send_update(LiveSelect.Component, live_select_id, options: [])
          {:noreply, socket}
      end
    end
  end

  def handle_event("live_select_change", _, socket), do: {:noreply, socket}

  defp metadata_keyword_name(%{"name" => name}) when is_binary(name), do: name
  defp metadata_keyword_name(%{name: name}) when is_binary(name), do: name
  defp metadata_keyword_name(_), do: nil

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

  @doc "Keywords from API as `keywords` or `keyword` (list or comma-separated string)."
  def keywords_list(movie) when is_map(movie) do
    raw = Map.get(movie, "keywords") || Map.get(movie, "keyword")

    case raw do
      list when is_list(list) ->
        list
        |> Enum.flat_map(&List.wrap/1)
        |> Enum.map(&to_string/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      s when is_binary(s) and s != "" ->
        s
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  def keywords_list(_), do: []

  # Rebuild the keywords form only when server-side movie identity or keyword list changes.
  # Rebuilding on every parent re-render (e.g. form phx-change) resets LiveSelect selection and drops new tags.
  defp keywords_form_digest(nil, _kws), do: {:none, nil}

  defp keywords_form_digest(movie, kws) when is_map(movie) do
    {Map.get(movie, "id"), :erlang.phash2(kws)}
  end
end
