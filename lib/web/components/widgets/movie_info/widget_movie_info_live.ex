defmodule Bonfire.PanDoRa.Web.WidgetMovieInfoLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Utils

  prop links, :any, default: []
  prop widget_title, :string, default: nil
  prop movie, :any, default: nil

  def mount(socket) do
    {:ok,
     socket
     |> assign(:available_sections, [])
     |> fetch_available_sections()}
  end

  # Handle the multi_select event for sezione
  def handle_event(
        "multi_select",
        %{"multi_select" => %{"edit_sezione" => sezione_json}} = attrs,
        socket
      ) do
    debug("Processing section update: #{inspect(attrs)}")

    if socket.assigns.movie do
      movie_id = socket.assigns.movie["id"]

      # Parse the JSON string to extract the section value
      sezione_data =
        case Jason.decode(sezione_json) do
          {:ok, data} -> data
          _ -> %{}
        end

      # Extract the value from the parsed JSON
      sezione_value = Map.get(sezione_data, "value", "")

      # Process the section field to ensure it's a list
      section_list =
        if is_binary(sezione_value) && String.trim(sezione_value) != "" do
          sezione_value
        else
          ""
        end

      # Prepare data for the API
      edit_data = %{
        id: movie_id,
        sezione: [section_list]
      }

      case Client.edit_movie(edit_data, socket) do
        {:ok, updated_fields} ->
          # Update the movie in the socket with the updated fields
          updated_movie = Map.merge(socket.assigns.movie, updated_fields)

          socket =
            socket
            |> assign(:movie, updated_movie)
            |> assign_flash(:info, l("Section updated successfully"))

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign_flash(:error, l("Failed to update section: %{reason}", reason: reason))

          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Handle the multi_select event for edizione
  def handle_event(
        "multi_select",
        %{"multi_select" => %{"edit_edizione" => edizione_json}} = attrs,
        socket
      ) do
    debug("Processing edizione update: #{inspect(attrs)}")

    if socket.assigns.movie do
      movie_id = socket.assigns.movie["id"]

      # Parse the JSON string to extract the edizione value
      edizione_data =
        case Jason.decode(edizione_json) do
          {:ok, data} -> data
          _ -> %{}
        end

      # Extract the value from the parsed JSON
      edizione_value = Map.get(edizione_data, "value", "")

      # Process the edizione field to ensure it's a valid value
      edizione =
        if is_binary(edizione_value) && String.trim(edizione_value) != "" do
          edizione_value
        else
          nil
        end

      # Prepare data for the API
      edit_data = %{
        id: movie_id,
        edizione: [edizione]
      }

      case Client.edit_movie(edit_data, socket) do
        {:ok, updated_fields} ->
          # Update the movie in the socket with the updated fields
          updated_movie = Map.merge(socket.assigns.movie, updated_fields)

          socket =
            socket
            |> assign(:movie, updated_movie)
            |> assign_flash(:info, l("Edizione updated successfully"))

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign_flash(:error, l("Failed to update edizione: %{reason}", reason: reason))

          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Fallback pattern to handle other multi_select events
  def handle_event("multi_select", attrs, socket) do
    debug("Unhandled multi_select event: #{inspect(attrs)}")
    {:noreply, socket}
  end

  def fetch_available_sections(socket) do
    # Define some default sections in case the API call fails
    default_sections = [
      {"3 Minuti", "3 Minuti"},
      {"Archivio", "Archivio"},
      {"Documentari", "Documentari"},
      {"Lungometraggi", "Lungometraggi"},
      {"Cortometraggi", "Cortometraggi"},
      {"Anteprima", "Anteprima"}
    ]

    case Client.fetch_grouped_metadata([],
           field: "sezione",
           per_page: 50,
           current_user: current_user(socket)
         ) do
      {:ok, metadata} ->
        sections = Map.get(metadata, "sezione", [])
        # Transform the sections into the format expected by MultiselectLive
        formatted_sections =
          sections
          |> Enum.map(fn
            %{"name" => name} when is_binary(name) -> {name, name}
            _ -> nil
          end)
          |> Enum.reject(&is_nil/1)

        # If we got valid sections, use them; otherwise use defaults
        if Enum.empty?(formatted_sections) do
          assign(socket, :available_sections, default_sections)
        else
          assign(socket, :available_sections, formatted_sections)
        end

      {:error, _reason} ->
        # Fall back to default sections if the API call fails
        assign(socket, :available_sections, default_sections)
    end
  end

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
end
