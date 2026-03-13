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
    socket = assign(socket, assigns)

    # Initial load: fetch lists, then fetch items sync so movie_in_lists is ready at first render
    lists_result = Client.my_lists(current_user: current_user(socket), per_page: 200)

    socket =
      socket
      |> handle_lists_result(lists_result)

    socket =
      if socket.assigns.lists != [] and socket.assigns.error == nil do
        opts = [current_user: current_user(socket), per_page: 1000]
        payload = fetch_list_items_async(socket.assigns.lists, opts, socket.assigns.movie_id)
        lists_with_icons = Enum.map(payload.lists_with_items, &add_icon_url(&1, opts))

        socket
        |> assign(:lists, lists_with_icons)
        |> assign(:movie_in_lists, payload.movie_in_lists)
        |> assign(:existing_lists, payload.existing_lists)
      else
        socket
      end

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
    opts = [current_user: current_user(socket)]

    socket
    |> assign(:lists, lists)
    |> assign(:pandora_opts, opts)
    |> assign(:loading, false)
    |> assign(:error, nil)
  end

  # Handle failed list fetch
  defp handle_lists_result(socket, {:error, error}) do
    socket
    |> assign(:lists, [])
    |> assign(:pandora_opts, [])
    |> assign(:loading, false)
    |> assign(:error, error)
  end

  # Fetches list items in parallel; returns payload for send_update.
  defp fetch_list_items_async(lists, opts, movie_id) do
    lists_with_items =
      lists
      |> Task.async_stream(
        fn list ->
          case Client.find_list_items(list["id"], opts) do
            {:ok, %{items: items}} -> Map.put(list, "items", items)
            _ -> Map.put(list, "items", [])
          end
        end,
        max_concurrency: 5,
        timeout: 15_000
      )
      |> Enum.map(fn {:ok, list} -> list end)

    existing_lists =
      Enum.filter(lists_with_items, fn list ->
        Enum.any?(list["items"], &(&1["id"] == movie_id))
      end)
      |> Enum.map(& &1["name"])

    movie_in_lists =
      Map.new(lists_with_items, fn list ->
        {list["id"], Enum.any?(list["items"], &(&1["id"] == movie_id))}
      end)

    %{lists_with_items: lists_with_items, existing_lists: existing_lists, movie_in_lists: movie_in_lists}
  end

  defp add_icon_url(list, opts), do: Map.put(list, "icon_url", Client.list_icon_url(list, opts))

  # Check if movie exists in any of user's lists (sync path, e.g. update_lists).
  defp check_movie_in_lists(socket) do
    opts = [current_user: current_user(socket), per_page: 1000]
    payload = fetch_list_items_async(socket.assigns.lists, opts, socket.assigns.movie_id)

    socket
    |> assign(:existing_lists, payload.existing_lists)
    |> assign(:movie_in_lists, payload.movie_in_lists)
  end

  # Update movie presence from lists (no API calls; used after add/remove).
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

  # Check if movie exists in a specific list.
  # Third arg: keyword opts or socket (converted to opts).
  def movie_in_list?(list_id, movie_id, %{assigns: _} = socket) do
    movie_in_list?(list_id, movie_id, [current_user: current_user(socket), per_page: 1000])
  end

  def movie_in_list?(list_id, movie_id, opts) when is_list(opts) do
    case Client.find_list_items(list_id, opts) do
      {:ok, %{items: items}} -> Enum.any?(items, &(&1["id"] == movie_id))
      _ -> false
    end
  end

  # Update lists after adding/removing movie
  defp update_lists(socket) do
    lists_result = Client.my_lists(current_user: current_user(socket), per_page: 200)

    socket
    |> handle_lists_result(lists_result)
    |> check_movie_in_lists()
  end
end
