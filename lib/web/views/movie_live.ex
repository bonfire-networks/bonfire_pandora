defmodule Bonfire.PanDoRa.Web.MovieLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Utils

  @behaviour Bonfire.UI.Common.LiveHandler

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.UserRequired]}

  def mount(_params, _session, socket) do
    debug("Mounting MovieLive")

    socket =
      socket
      |> assign(:nav_items, Bonfire.Common.ExtensionModule.default_nav())
      |> assign(:back, true)
      |> assign(:deleting_annotation_id, nil)
      |> assign(:note_content, "")
      # Add this to track which annotation is being edited
      |> assign(:editing_annotation, nil)
      # Add this to track if we're in editing mode
      |> assign(:editing_mode, false)

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
        # Initialize note_content
        |> assign(:note_content, "")
        |> assign(:public_notes, public_notes)
        # Initialize editing state
        |> assign(:editing_annotation, nil)
        # Initialize editing mode
        |> assign(:editing_mode, false)
        |> assign(:sidebar_widgets,
          users: [
            secondary: [
              {Bonfire.PanDoRa.Web.WidgetMovieInfoLive,
               [
                 type: Surface.LiveComponent,
                 id: "movie_info",
                 movie: movie,
                 widget_title: "Movie Info"
               ]}
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
           # assuming this is your layer ID for public notes
           layer: "publicnotes",
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
       # Clear the note content after successful submission
       |> assign(:note_content, "")
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
        updated_notes =
          Enum.reject(socket.assigns.public_notes, fn note ->
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
    annotation_to_edit =
      Enum.find(socket.assigns.public_notes, fn note ->
        note["id"] == note_id
      end)

    if annotation_to_edit do
      # Set the form fields with the annotation data
      socket =
        socket
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
    socket =
      socket
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
      updated_notes =
        Enum.map(socket.assigns.public_notes, fn note ->
          if note["id"] == annotation_id do
            updated_annotation
          else
            note
          end
        end)

      # Reset the editing state
      socket =
        socket
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

    # Process the director and section fields to ensure they're lists
    movie_data =
      movie_data
      |> process_director_field()
      |> process_section_field()

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

  # Handle the live_select_change event for autocomplete
  def handle_event("live_select_change", %{"field" => field, "text" => search_text}, socket) do
    # Extract the field name from the form field identifier
    field_name =
      case field do
        "movie_form_movie[sezione]" -> "sezione"
        _ -> nil
      end

    if field_name do
      # Perform a search for sections matching the text
      case Client.fetch_grouped_metadata([], field: field_name, per_page: 10) do
        {:ok, metadata} ->
          sections = Map.get(metadata, field_name, [])
          # Filter sections that match the search text
          matching_sections =
            sections
            |> Enum.filter(fn %{"name" => name} ->
              String.contains?(String.downcase(name), String.downcase(search_text))
            end)
            |> Enum.map(fn %{"name" => name} -> {name, name} end)

          # Send the matching options back to the LiveSelect component
          send_update(Bonfire.UI.Common.LiveSelectIntegrationLive,
            id: "#{field}_live_select_component",
            options: matching_sections
          )

          {:noreply, socket}

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Process the director field to ensure it's a list
  defp process_director_field(movie_data) do
    if Map.has_key?(movie_data, "director") do
      director = movie_data["director"]

      # Split the comma-separated string into a list, trim whitespace, and remove empty entries
      director_list =
        director
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&(&1 != ""))

      # Update the movie_data with the director as a list
      Map.put(movie_data, "director", director_list)
    else
      movie_data
    end
  end

  # Process the section field to ensure it's a list
  defp process_section_field(movie_data) do
    if Map.has_key?(movie_data, "sezione") do
      section = movie_data["sezione"]

      section_list =
        cond do
          # If it's already a list of strings, keep it as is
          is_list(section) && Enum.all?(section, &is_binary/1) ->
            section

          # If it's a list of maps with "value" key (from LiveSelect), extract values
          is_list(section) && Enum.all?(section, &(is_map(&1) && Map.has_key?(&1, "value"))) ->
            Enum.map(section, & &1["value"])

          # If it's a single string, convert to a list
          is_binary(section) && String.trim(section) != "" ->
            # Check if it's a comma-separated list
            if String.contains?(section, ",") do
              section
              |> String.split(",")
              |> Enum.map(&String.trim/1)
              |> Enum.filter(&(&1 != ""))
            else
              [section]
            end

          # If it's nil or empty string, use an empty list
          true ->
            []
        end

      # Update the movie_data with the section as a list
      Map.put(movie_data, "sezione", section_list)
    else
      movie_data
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
