defmodule Bonfire.PanDoRa.Web.MovieLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Utils

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
        |> assign(:in_timestamp, nil)
        |> assign(:out_timestamp, nil)
        |> assign(:note_content, "") # Initialize note_content
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
  end


  def handle_event("mark_in_timestamp", %{"timestamp" => timestamp} = _params, socket) do
    # Handle the in timestamp - for example, store it in socket assigns
    socket =
      socket
      |> assign(:in_timestamp, timestamp)
    {:noreply, socket}
  end

  def handle_event("mark_out_timestamp", %{"timestamp" => timestamp}, socket) do
    # Handle the out timestamp - for example, store it in socket assigns
    {:noreply, assign(socket, :out_timestamp, timestamp)}
  end

  def handle_event("validate_note", %{"note" => note}, socket) do
    # Simple validation - ensure note is not empty
    valid = String.trim(note) != ""
    # Store the note content in socket assigns to preserve it
    {:noreply, socket |> assign(:note_valid, valid) |> assign(:note_content, note)}
  end

  def handle_event("create_note", %{"note" => note}, socket) do
    with movie_id <- socket.assigns.movie["id"],
         in_timestamp <- socket.assigns.in_timestamp || 0.0,
         out_timestamp <- socket.assigns.out_timestamp || in_timestamp,
         annotation_data = %{
           item: movie_id,
           layer: "publicnotes", # assuming this is your layer ID for public notes
           in: in_timestamp,
           out: out_timestamp,
           value: note
         },
         {:ok, response} <- Client.add_annotation(annotation_data) do

      # Update the public_notes list in the socket
      updated_notes = [response | socket.assigns.public_notes]

      {:noreply,
       socket
       |> assign(:public_notes, updated_notes)
       |> assign(:note_content, "") # Clear the note content after successful submission
       |> assign_flash(:info, l("Annotation added successfully"))}
    else
      error ->
        error("Error creating note: #{inspect(error)}")
        {:noreply, assign_flash(socket, :error, l("Could not create note"))}
    end
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


end
