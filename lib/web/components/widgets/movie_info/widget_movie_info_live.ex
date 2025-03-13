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

    case Client.fetch_grouped_metadata([], field: "sezione", per_page: 50) do
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
