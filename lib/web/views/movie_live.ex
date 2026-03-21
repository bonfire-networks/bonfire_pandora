defmodule Bonfire.PanDoRa.Web.MovieLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Utils
  alias Bonfire.PanDoRa.Archives

  @behaviour Bonfire.UI.Common.LiveHandler

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.UserRequired]}

  def mount(_params, _session, socket) do
    debug("Mounting MovieLive")

    socket =
      socket
      |> assign(:back, true)
      |> assign(:deleting_annotation_id, nil)
      |> assign(:note_content, "")
      |> assign(:in_timestamp, nil)
      |> assign(:out_timestamp, nil)
      |> assign(:public_notes, [])
      # Add this to track which annotation is being edited
      |> assign(:editing_annotation, nil)
      # Add this to track if we're in editing mode
      |> assign(:editing_mode, false)
      |> assign(:movie, nil)
      |> assign(:video_url, nil)
      |> assign(:movie_heading_full, nil)
      |> assign(:movie_heading_truncated, false)

    {:ok, socket}
  end

  def handle_params(%{"id" => id}, uri, socket) do
    # Seek from link: ?in=&out= (seconds, same format as annotation-checkpoint badge)
    {in_ts, out_ts} = parse_seek_params(uri)
    opts = [current_user: current_user(socket)]

    movie_task = Task.async(fn -> Client.get_movie(id, opts) end)
    notes_task = Task.async(fn -> Client.fetch_annotations(id, opts) end)
    movie_result = Task.await(movie_task)
    notes_result = Task.await(notes_task)

    with {:ok, movie} <- movie_result,
         {:ok, public_notes} <- notes_result do
      video_url =
        Client.video_url(
          to_string(movie["id"] || ""),
          Client.best_video_filename(movie),
          current_user: current_user(socket)
        )

      raw_title = movie["title"] |> to_string()
      header_title = page_title_for_header(raw_title)
      title_truncated? = raw_title != "" and header_title != raw_title

      socket =
        socket
        |> assign(:params, id)
        |> assign(:back, true)
        |> assign(:page_title, header_title)
        |> assign(:movie_heading_full, raw_title)
        |> assign(:movie_heading_truncated, title_truncated?)
        |> assign(:movie, movie)
        |> assign(:video_url, video_url)
        |> assign(:in_timestamp, in_ts)
        |> assign(:out_timestamp, out_ts)
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
          |> assign(:video_url, nil)
          |> assign(:public_notes, [])
          |> assign(:in_timestamp, nil)
          |> assign(:out_timestamp, nil)
          |> assign(:note_content, "")
          |> assign(:editing_annotation, nil)
          |> assign(:editing_mode, false)
          |> assign(:back, true)
          |> assign(:page_title, "Movie not found")
          |> assign(:movie_heading_full, nil)
          |> assign(:movie_heading_truncated, false)

        {:noreply, socket}
    end
  end

  # Short header label keeps PageHeaderLive flex row within viewport (bonfire_ui_common is unchanged).
  # Full title is shown in the template when truncated.
  @header_title_max_graphemes 48

  defp page_title_for_header(title) when is_binary(title) and title != "" do
    if String.length(title) <= @header_title_max_graphemes do
      title
    else
      String.slice(title, 0, @header_title_max_graphemes) <> "…"
    end
  end

  defp page_title_for_header(_), do: ""

  defp parse_seek_params(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %{query: nil} -> {nil, nil}
      %{query: query} ->
        params = URI.decode_query(query)
        in_ts = parse_float_param(params["in"])
        out_ts = parse_float_param(params["out"])
        {in_ts, out_ts}
    end
  end

  defp parse_seek_params(_), do: {nil, nil}

  defp parse_float_param(nil), do: nil
  defp parse_float_param(s) when is_binary(s) do
    case Float.parse(String.trim(s)) do
      {n, _} when n >= 0 -> n
      _ -> nil
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

  def handle_event("add_annotation", %{"note" => note}, socket) do
    opts = [current_user: current_user(socket)]
    opts = if movie_id = socket.assigns[:params], do: [movie_id: movie_id] ++ opts, else: opts

    with {:ok, annotation} <-
           Archives.add_annotation(
             socket.assigns.movie,
             note,
             socket.assigns.in_timestamp,
             socket.assigns.out_timestamp,
             opts
           ) do
      # Update the public_notes list in the socket
      updated_notes = [annotation | socket.assigns.public_notes]

      {:noreply,
       socket
       |> assign(:public_notes, updated_notes)
       # Clear the note content after successful submission
       |> assign(:note_content, "")
       |> assign_flash(:info, l("Annotation added successfully"))}
    else
      error ->
        error(error, "Error creating note")
        {:noreply, assign_flash(socket, :error, l("Could not create note"))}
    end
  end

  # TODO: deprecate in favour of standard Post deletion
  def handle_event("delete_annotation", %{"note-id" => note_id}, socket) do
    case Client.remove_annotation(note_id, current_user: current_user(socket)) do
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
        error(error, "Error deleting annotation")
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
  def handle_event("update_annotation", %{"note" => note}, socket) do
    annotation_id = socket.assigns.editing_annotation["id"]
    in_timestamp = socket.assigns.in_timestamp
    out_timestamp = socket.assigns.out_timestamp

    edit_data = %{
      id: annotation_id,
      in: in_timestamp,
      out: out_timestamp,
      value: note
    }

    case Client.edit_annotation(edit_data, current_user: current_user(socket)) do
      {:ok, updated_annotation} ->
        updated_notes =
          Enum.map(socket.assigns.public_notes, fn n ->
            if n["id"] == annotation_id, do: updated_annotation, else: n
          end)

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

      error ->
        error(error, "Error updating annotation")
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
      |> process_featuring_field()
      |> process_keywords_field()
      |> process_section_field()

    # Build edit_data from whitelisted fields (avoids String.to_existing_atom on dynamic keys)
    edit_data =
      %{id: movie_id}
      |> put_edit_field(:title, movie_data)
      |> put_edit_field(:director, movie_data)
      |> put_edit_field(:summary, movie_data)
      |> put_edit_field(:year, movie_data)
      |> put_edit_field(:featuring, movie_data)
      |> put_edit_field(:country, movie_data)
      |> put_edit_field(:language, movie_data)
      |> put_edit_field(:keywords, movie_data)
      |> put_edit_field(:sezione, movie_data)

    case Client.edit_movie(edit_data, current_user: current_user(socket)) do
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

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_selezionato", attrs, socket) do
    debug("Processing selezionato update: #{inspect(attrs)}")

    if socket.assigns.movie do
      movie_id = socket.assigns.movie["id"]

      # Extract the value from attrs - it can be %{value: "on"} or %{}
      toggle_value = Map.get(attrs, "value", nil)

      # Determine the selezionato value based on the toggle state
      selezionato_value =
        if toggle_value == "on" do
          "yes"
        else
          "no"
        end

      # Prepare data for the API
      edit_data = %{
        id: movie_id,
        selezionato: [selezionato_value]
      }

      case Client.edit_movie(edit_data, socket) do
        {:ok, updated_fields} ->
          # Update the movie in the socket with the updated fields
          updated_movie = Map.merge(socket.assigns.movie, updated_fields)

          socket =
            socket
            |> assign(:movie, updated_movie)
            |> assign_flash(:info, l("Selection status updated"))

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign_flash(
              :error,
              l("Failed to update selection status: %{reason}", reason: reason)
            )

          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Handle the live_select_change event for autocomplete
  def handle_event(
        "live_select_change",
        %{"field" => field, "text" => search_text, "id" => live_select_id},
        socket
      ) do
    # Extract the field name from the form field identifier
    field_name =
      case field do
        "multi_select_edit_sezione" -> "sezione"
        "multi_select_edit_edizione" -> "edizione"
        # "multi_select_edit_genre" -> "genre"
        _ -> nil
      end

    if field_name do
      # Perform a search for sections matching the text
      case Client.fetch_grouped_metadata([],
             field: field_name,
             per_page: 10,
             current_user: current_user(socket)
           ) do
        {:ok, %{filters: filters}} ->
          sections = Map.get(filters, field_name, [])
          # Filter sections that match the search text
          matching_sections =
            sections
            |> Enum.filter(fn %{"name" => name} ->
              String.contains?(String.downcase(name), String.downcase(search_text))
            end)
            |> Enum.map(fn %{"name" => name} -> {name, %{id: name, name: name, value: name}} end)

          debug("Matching sections: #{inspect(matching_sections)}")
          maybe_send_update(LiveSelect.Component, live_select_id, options: matching_sections)
          # # Send the matching options back to the LiveSelect component
          # send_update(Bonfire.UI.Common.LiveSelectIntegrationLive,
          #   id: "#{field}_live_select_component",
          #   options: matching_sections
          # )

          {:noreply, socket}

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(msg, socket) do
    Bonfire.UI.Common.LiveHandlers.handle_info(msg, socket, __MODULE__)
  end

  defp put_edit_field(acc, key, movie_data) when is_atom(key) do
    str_key = to_string(key)
    case Map.fetch(movie_data, str_key) do
      :error -> acc
      {:ok, value} -> Map.put(acc, key, value)
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

  # Process the featuring field to ensure it's a list (comma-separated input)
  defp process_featuring_field(movie_data) do
    if Map.has_key?(movie_data, "featuring") do
      featuring_list =
        movie_data["featuring"]
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&(&1 != ""))

      Map.put(movie_data, "featuring", featuring_list)
    else
      movie_data
    end
  end

  # Keywords: same shape as director/featuring for Pandora edit API
  defp process_keywords_field(movie_data) do
    if Map.has_key?(movie_data, "keywords") do
      kw_list =
        case movie_data["keywords"] do
          list when is_list(list) ->
            list
            |> Enum.flat_map(&List.wrap/1)
            |> Enum.map(&to_string/1)
            |> Enum.map(&String.trim/1)
            |> Enum.filter(&(&1 != ""))

          s ->
            s
            |> to_string()
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.filter(&(&1 != ""))
        end

      Map.put(movie_data, "keywords", kw_list)
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
  # def fetch_movies(id, opts) do
  #   debug("Fetching movie with ID: #{inspect(id)}")

  #   case Client.get_movie(id, opts) do
  #     {:ok, movie} ->
  #       debug("Fetched movie: #{inspect(movie)}")
  #       movie

  #     error ->
  #       debug("Error fetching movie: #{inspect(error)}")
  #       nil
  #   end
  # end
end
