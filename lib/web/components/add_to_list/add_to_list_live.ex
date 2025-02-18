defmodule Bonfire.PanDoRa.Components.AddToListLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias PanDoRa.API.Client

  prop movie_id, :string, required: true

  def mount(socket) do
    socket =
      socket
      |> assign(:lists, [])
      |> assign(:loading, true)
      |> assign(:error, nil)

    {:ok, socket}
  end

  def update(assigns, socket) do
    # Fetch user's lists when component is updated
    lists_result = fetch_my_lists()

    socket =
      socket
      |> assign(assigns)
      |> handle_lists_result(lists_result)

    {:ok, socket}
  end

  def handle_event("add_to_list", %{"id" => list_id}, socket) do
    case Client.add_list_items(list_id, items: [socket.assigns.movie_id]) do
      {:ok, _} ->
        # Bonfire.UI.Common.OpenModalLive.close()

        {:noreply,
         socket
         |> assign_flash(:info, l("Movie added to list successfully"))}

      {:error, error} ->
        {:noreply,
         socket
         |> assign_flash(:error, error)}
    end
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

  # Fetch lists for the current user
  defp fetch_my_lists() do
    Client.find_lists(
      keys: ["id", "name", "status", "posterFrames"],
      sort: [%{key: "name", operator: "+"}],
      type: :user
    )
  end
end
