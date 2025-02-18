defmodule Bonfire.PanDoRa.Web.WidgetPublicListsLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias PanDoRa.API.Client

  prop user, :any, default: nil

  def update(assigns, socket) do
    lists_result = fetch_public_lists()

    socket =
      socket
      |> assign(assigns)
      |> handle_lists_result(lists_result)

    {:ok, socket}
  end

  # Handle successful list fetch
  defp handle_lists_result(socket, {:ok, %{items: lists}}) do
    socket
    |> assign(:lists, lists)
    |> assign(:loading, false)
    |> assign(:error, nil)
  end

  # Handle failed list fetch
  defp handle_lists_result(socket, {:error, error}) do
    socket
    |> assign(:lists, [])
    |> assign(:loading, false)
    |> assign(:error, error)
  end

  # Fetch public lists for a specific user
  defp fetch_public_lists() do
    Client.find_lists(
      keys: ["id", "description", "poster_frames", "posterFrames", "name", "status", "user"],
      sort: [%{key: "name", operator: "+"}],
      type: :user,
      query: [
        %{key: "status", operator: "==", value: "public"}
      ]
    )
  end
end
