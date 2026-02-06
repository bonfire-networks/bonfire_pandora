defmodule Bonfire.PanDoRa.Web.ListLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias PanDoRa.API.Client

  @behaviour Bonfire.UI.Common.LiveHandler
  @default_per_page 20

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(%{"id" => list_id} = _params, _session, socket) do
    debug("Mounting ListLive")

    socket =
      socket
      |> stream_configure(:list_items,
        # Use string key "id" instead of atom :id
        dom_id: &"list-item-#{&1["id"]}"
      )
      |> stream(:list_items, [])
      |> assign(:list, %{})
      |> assign(:back, true)
      |> assign(:list_id, list_id)
      |> assign(:page, 0)
      |> assign(:per_page, @default_per_page)
      |> assign(:has_more_items, false)
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:uploaded_files, nil)

    if socket_connected?(socket) do
      send(self(), :load_initial_data)
      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  def handle_info(:load_initial_data, socket) do
    %{list_id: list_id} = socket.assigns

    list_result = fetch_list(list_id, current_user: current_user(socket))
    items_result = fetch_list_items(list_id, current_user: current_user(socket))

    socket =
      socket
      |> handle_list_result(list_result)
      |> handle_items_result(items_result)

    {:noreply, socket}
  end

  def handle_event("load_more", _params, socket) do
    %{list_id: list_id, page: page, per_page: per_page} = socket.assigns

    next_page = page + 1
    items_result = fetch_list_items(list_id, page: next_page, per_page: per_page)

    {:noreply, socket |> assign(:page, next_page) |> handle_items_result(items_result)}
  end

  def handle_event("validate_update_list", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_list", %{"list" => list_params} = _params, socket) do
    debug(list_params, "update_list_params")
    debug(socket.assigns.uploaded_files, "Uploaded files during list update")

    list_params =
      case socket.assigns.uploaded_files do
        %{} = uploaded_media ->
          debug(uploaded_media, "Adding icon to list params")
          Map.put(list_params, "posterFrames", [{uploaded_media.path, 0}])

        _ ->
          debug("No icon available")
          list_params
      end

    # Extract the ID and remove it from params to be updated
    id = Map.get(list_params, "id")
    update_params = Map.drop(list_params, ["id"])

    case Client.edit_list(id, update_params, current_user: current_user(socket)) do
      {:ok, updated_list} ->
        {:noreply,
         socket
         |> assign(:list, updated_list)
         |> assign(:page_title, e(updated_list, "name", l("List")))
         |> assign(:uploaded_files, nil)
         |> assign_flash(:info, l("List updated successfully"))}

      {:error, error} ->
        {:noreply,
         socket
         |> assign_flash(:error, error)}
    end
  end

  def handle_info({:update_list_icon, media}, socket) do
    debug(media, "Received list icon update")

    {:noreply,
     socket
     |> assign(uploaded_files: media)}
  end

  def handle_info(msg, socket) do
    {:noreply, socket}
  end

  # Handle successful list fetch
  defp handle_list_result(socket, {:ok, list}) do
    socket
    |> assign(:list, list)
    |> assign(:page_title, e(list, "name", l("List")))
    |> assign(:loading, false)
    |> assign(:error, nil)
  end

  # Handle failed list fetch
  defp handle_list_result(socket, {:error, error}) do
    socket
    |> assign(:list, nil)
    |> assign(:loading, false)
    |> assign(:error, error)
  end

  # Handle successful items fetch
  defp handle_items_result(socket, {:ok, %{items: items, total: total}}) do
    socket
    |> stream(:list_items, items)
    |> assign(:has_more_items, length(items) >= socket.assigns.per_page)
    |> assign(:items_loading, false)
    |> assign(:items_error, nil)
  end

  # Handle failed items fetch
  defp handle_items_result(socket, {:error, error}) do
    socket
    |> stream(:list_items, [])
    |> assign(:has_more_items, false)
    |> assign(:items_loading, false)
    |> assign(:items_error, error)
  end

  # Fetch a specific list by ID
  defp fetch_list(id, opts) do
    Client.get_list(id, opts)
  end

  # Fetch items for a specific list
  defp fetch_list_items(list_id, opts) do
    Client.find_list_items(list_id, opts)
  end
end
