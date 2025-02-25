defmodule Bonfire.PanDoRa.Web.MovieLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias PanDoRa.API.Client

  @behaviour Bonfire.UI.Common.LiveHandler

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    debug("Mounting MovieLive")

    socket =
      socket
      |> assign(:nav_items, Bonfire.Common.ExtensionModule.default_nav())
      |> assign(:back, true)

    {:ok, socket}
  end

  def handle_params(%{"id" => id}, _view, socket) do
    # debug("Testing annotations for movie: #{id}")
    # annotations_result = Client.fetch_annotations(id)
    # debug("Annotations result: #{inspect(annotations_result)}")

    with {:ok, movie} <- Client.get_movie(id),
         {:ok, public_notes} <- Client.fetch_annotations(id) do
      socket =
        socket
        |> assign(:params, id)
        |> assign(:back, true)
        |> assign(:page_title, movie["title"] || "")
        |> assign(:movie, movie)
        |> assign(:public_notes, public_notes)
        |> assign(:sidebar_widgets,
          users: [
            secondary: [
              {Bonfire.PanDoRa.Web.WidgetMovieInfoLive,
               [movie: movie, widget_title: "Movie Info"]}
            ]
          ]
        )

      {:noreply, socket}
    else
      error ->
        debug("Error fetching movie: #{inspect(error)}")

        socket =
          socket
          |> assign(:movie, nil)
          |> assign(:back, true)
          |> assign(:page_title, "Movie not found")

        {:noreply, socket}
    end

    # case fetch_movies(id) do
    #   nil ->
    #     socket =
    #       socket
    #       |> assign(:movie, nil)
    #       |> assign(:back, true)
    #       |> assign(:page_title, "Movie not found")

    #     {:noreply, socket}

    #   movie ->
    #     debug("Movie found: #{inspect(movie)}")

    #     socket =
    #       socket
    #       |> assign(:params, id)
    #       |> assign(:back, true)
    #       |> assign(:page_title, movie["title"] || "")
    #       |> assign(:movie, movie)
    #       |> assign(:sidebar_widgets,
    #         users: [
    #           secondary: [
    #             {Bonfire.PanDoRa.Web.WidgetMovieInfoLive,
    #              [movie: movie, widget_title: "Movie Info"]},
    #             {Bonfire.PanDoRa.Web.WidgetMoviePropertiesLive,
    #              [movie: movie, widget_title: "Movie Properties"]}
    #           ]
    #         ]
    #       )

    #     {:noreply, socket}
    # end
  end

  def handle_event("mark_in_timestamp", %{"timestamp" => timestamp}, socket) do
    # Handle the in timestamp - for example, store it in socket assigns
    {:noreply, assign(socket, :in_timestamp, timestamp)}
  end

  def handle_event("mark_out_timestamp", %{"timestamp" => timestamp}, socket) do
    # Handle the out timestamp - for example, store it in socket assigns
    {:noreply, assign(socket, :out_timestamp, timestamp)}
  end

  # Add a private function to fetch movies
  def fetch_movies(id) do
    debug("Fetching movie with ID: #{inspect(id)}")

    case Client.get_movie(id) do
      {:ok, movie} ->
        debug("Fetched movie: #{inspect(movie)}")
        movie

      error ->
        debug("Error fetching movie: #{inspect(error)}")
        nil
    end
  end

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

    cond do
      hours > 0 -> "#{hours}h #{minutes}min"
      minutes > 0 -> "#{minutes}min"
      true -> "< 1min"
    end
  end
end
