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
      |> assign(:deleting_annotation_id, nil)
      |> assign(:editing_annotation, nil)  # Add this to track which annotation is being edited
      |> assign(:editing_mode, false)      # Add this to track if we're in editing mode

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
        |> assign(:editing_annotation, nil)  # Initialize editing state
        |> assign(:editing_mode, false)      # Initialize editing mode
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

  def handle_event("delete_annotation", %{"note-id" => note_id}, socket) do
    case Client.remove_annotation(note_id) do
      {:ok, _response} ->
        # Remove the deleted note from the public_notes list
        updated_notes = Enum.reject(socket.assigns.public_notes, fn note ->
          note["id"] == note_id
        end)

        # Update the socket with the new list of notes
        Bonfire.UI.Common.OpenModalLive.close()

        {:noreply,
         socket
         |> assign(:public_notes, updated_notes)
         |> assign_flash(:info, l("Annotation deleted successfully"))}
      error ->
        error("Error deleting annotation: #{inspect(error)}")
        {:noreply, assign_flash(socket, :error, l("Could not delete annotation"))}
    end
  end

  # Handle the edit annotation button click
  def handle_event("edit_annotation", %{"note-id" => note_id}, socket) do
    # Find the annotation to edit
    annotation_to_edit = Enum.find(socket.assigns.public_notes, fn note ->
      note["id"] == note_id
    end)

    if annotation_to_edit do
      # Set the form fields with the annotation data
      socket = socket
        |> assign(:editing_mode, true)
        |> assign(:editing_annotation, annotation_to_edit)
        |> assign(:note_content, annotation_to_edit["value"])
        |> assign(:in_timestamp, annotation_to_edit["in"])
        |> assign(:out_timestamp, annotation_to_edit["out"])

      {:noreply, socket}
    else
      {:noreply, assign_flash(socket, :error, l("Could not find annotation to edit"))}
    end
  end

  # Handle canceling the edit
  def handle_event("cancel_edit", _params, socket) do
    socket = socket
      |> assign(:editing_mode, false)
      |> assign(:editing_annotation, nil)
      |> assign(:note_content, "")
      |> assign(:in_timestamp, nil)
      |> assign(:out_timestamp, nil)

    {:noreply, socket}
  end

  # Handle submitting the edit
  def handle_event("update_note", %{"note" => note}, socket) do
    with annotation_id <- socket.assigns.editing_annotation["id"],
         in_timestamp <- socket.assigns.in_timestamp,
         out_timestamp <- socket.assigns.out_timestamp,
         edit_data = %{
           id: annotation_id,
           in: in_timestamp,
           out: out_timestamp,
           value: note
         },
         {:ok, updated_annotation} <- Client.edit_annotation(edit_data) do

      # Update the public_notes list in the socket
      updated_notes = Enum.map(socket.assigns.public_notes, fn note ->
        if note["id"] == annotation_id do
          updated_annotation
        else
          note
        end
      end)

      # Reset the editing state
      socket = socket
        |> assign(:public_notes, updated_notes)
        |> assign(:editing_mode, false)
        |> assign(:editing_annotation, nil)
        |> assign(:note_content, "")
        |> assign(:in_timestamp, nil)
        |> assign(:out_timestamp, nil)
        |> assign_flash(:info, l("Annotation updated successfully"))

      {:noreply, socket}
    else
      error ->
        error("Error updating annotation: #{inspect(error)}")
        {:noreply, assign_flash(socket, :error, l("Could not update annotation"))}
    end
  end

  # Handle editing a movie
  def handle_event("edit_movie", %{"movie" => movie_data}, socket) do
    movie_id = socket.assigns.movie["id"]

    # Convert string keys to atoms for the API client
    edit_data =
      movie_data
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.put(:id, movie_id)

    case Client.edit_movie(edit_data) do
      {:ok, updated_fields} ->
        # Update the movie in the socket with the updated fields
        updated_movie = Map.merge(socket.assigns.movie, updated_fields)

        socket =
          socket
          |> assign(:movie, updated_movie)
          |> assign_flash(:info, l("Movie updated successfully"))

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign_flash(:error, l("Failed to update movie: %{reason}", reason: reason))

        {:noreply, socket}
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
