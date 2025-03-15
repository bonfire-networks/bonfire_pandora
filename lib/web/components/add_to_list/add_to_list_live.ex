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
      |> assign(:existing_lists, [])
      |> assign(:movie_in_lists, %{})

    {:ok, socket}
  end

  def update(assigns, socket) do
    # Fetch user's lists when component is updated
    lists_result = Client.my_lists(current_user: current_user(socket))

    socket =
      socket
      |> assign(assigns)
      |> handle_lists_result(lists_result)
      |> check_movie_in_lists()
      |> update_movie_presence()

    {:ok, socket}
  end

  def handle_event("add_to_list", %{"id" => list_id}, socket) do
    if movie_in_list?(list_id, socket.assigns.movie_id, socket) do
      {:noreply,
       socket
       |> assign_flash(:error, l("Movie is already in this list"))}
    else
      case Client.add_list_items(list_id,
             items: [socket.assigns.movie_id],
             current_user: current_user(socket)
           ) do
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
  end

  def handle_event("toggle_in_list", %{"id" => list_id}, socket) do
    current_presence = get_in(socket.assigns.movie_in_lists, [list_id]) || false

    if current_presence do
      case Client.remove_list_items(list_id,
             items: [socket.assigns.movie_id],
             current_user: current_user(socket)
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> update_movie_presence_for_list(list_id, false)
           |> assign_flash(:info, l("Movie removed from list"))}

        {:error, error} ->
          {:noreply,
           socket
           |> assign_flash(:error, error)}
      end
    else
      case Client.add_list_items(list_id,
             items: [socket.assigns.movie_id],
             current_user: current_user(socket)
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> update_movie_presence_for_list(list_id, true)
           |> assign_flash(:info, l("Movie added to list"))}

        {:error, error} ->
          {:noreply,
           socket
           |> assign_flash(:error, error)}
      end
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

  # Check if movie exists in any of user's lists
  defp check_movie_in_lists(socket) do
    lists_with_items =
      Enum.map(socket.assigns.lists, fn list ->
        case Client.find_list_items(list["id"], socket) do
          {:ok, %{items: items}} -> Map.put(list, "items", items)
          _ -> Map.put(list, "items", [])
        end
      end)

    existing_lists =
      Enum.filter(lists_with_items, fn list ->
        Enum.any?(list["items"], &(&1["id"] == socket.assigns.movie_id))
      end)
      |> Enum.map(& &1["name"])

    assign(socket, :existing_lists, existing_lists)
  end

  # Update movie presence in all lists
  defp update_movie_presence(socket) do
    movie_in_lists =
      Enum.reduce(socket.assigns.lists, %{}, fn list, acc ->
        Map.put(acc, list["id"], movie_in_list?(list["id"], socket.assigns.movie_id, socket))
      end)

    assign(socket, :movie_in_lists, movie_in_lists)
  end

  # Update movie presence for a specific list
  defp update_movie_presence_for_list(socket, list_id, presence) do
    assign(socket, :movie_in_lists, Map.put(socket.assigns.movie_in_lists, list_id, presence))
  end

  # Check if movie exists in a specific list
  def movie_in_list?(list_id, movie_id, opts) do
    case Client.find_list_items(list_id, opts) do
      {:ok, %{items: items}} -> Enum.any?(items, &(&1["id"] == movie_id))
      _ -> false
    end
  end

  # Update lists after adding/removing movie
  defp update_lists(socket) do
    lists_result = Client.my_lists(current_user: current_user(socket))

    socket
    |> handle_lists_result(lists_result)
    |> check_movie_in_lists()
  end
end
