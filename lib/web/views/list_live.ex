defmodule Bonfire.PanDoRa.Web.ListLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.Auth

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
      |> assign(:all_items, [])
      |> assign(:has_more_items, false)
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:uploaded_files, nil)
      |> assign_pandora_urls()

    if socket_connected?(socket) do
      send(self(), :load_initial_data)
      {:ok, socket}
    else
      # Full page load (e.g. open in new tab): load data synchronously so initial HTML includes it
      socket = do_load_initial_data(socket)
      {:ok, socket}
    end
  end

  defp assign_pandora_urls(socket) do
    socket
    |> assign(:pandora_token, Auth.pandora_token(current_user: socket.assigns[:current_user]))
    |> assign(:pandora_base_url, String.trim_trailing(Client.get_pandora_url() || "", "/"))
  end

  def list_icon_src(pandora_token, pandora_base_url, current_user, list) do
    Bonfire.PanDoRa.Web.MyListsLive.list_icon_src(pandora_token, pandora_base_url, current_user, list)
  end

  def handle_info(:load_initial_data, socket) do
    {:noreply, do_load_initial_data(socket)}
  end

  defp do_load_initial_data(socket) do
    %{list_id: list_id, per_page: per_page} = socket.assigns
    opts = [current_user: current_user(socket)]
    items_opts = [page: 0, per_page: per_page] ++ opts

    list_task = Task.async(fn -> fetch_list(list_id, opts) end)
    items_task = Task.async(fn -> fetch_list_items(list_id, items_opts) end)
    list_result = Task.await(list_task)
    items_result = Task.await(items_task)

    socket
    |> handle_list_result(list_result)
    |> handle_items_result(items_result)
  end

  def handle_event("load_more", _params, socket) do
    %{list_id: list_id, page: page, per_page: per_page} = socket.assigns

    next_page = page + 1
    items_result =
      fetch_list_items(list_id,
        page: next_page,
        per_page: per_page,
        current_user: current_user(socket)
      )

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
  # Accumulate items and always replace stream to avoid stream_insert + static li misalignment.
  defp handle_items_result(socket, {:ok, %{items: items} = result}) do
    all_items =
      if socket.assigns.page == 0 do
        items
      else
        socket.assigns.all_items ++ items
      end

    # Conservative: show Load More when we got a full page (might be more). Hide only when we got fewer.
    per_page = socket.assigns.per_page
    has_more =
      case result do
        %{has_more: h} when is_boolean(h) -> h
        _ -> length(items) >= per_page
      end
    # If API says no more but we got a full page, show button anyway (API may not report total)
    has_more = has_more or length(items) >= per_page

    socket
    |> assign(:all_items, all_items)
    |> stream(:list_items, all_items)
    |> assign(:has_more_items, has_more)
    |> assign(:items_loading, false)
    |> assign(:items_error, nil)
  end

  # Handle failed items fetch
  defp handle_items_result(socket, {:error, error}) do
    socket
    |> assign(:all_items, [])
    |> stream(:list_items, [])
    |> assign(:has_more_items, false)
    |> assign(:items_loading, false)
    |> assign(:items_error, error)
  end

  # Fetch a specific list by ID
  defp fetch_list(id, opts) do
    Client.get_list(id, opts)
  end

  # Fetch items for a specific list. Use Client.find (same as SearchLive) for correct pagination.
  defp fetch_list_items(list_id, opts) do
    per_page = Keyword.get(opts, :per_page, @default_per_page)
    page = Keyword.get(opts, :page, 0)
    start_idx = page * per_page

    case Client.find(
           conditions: [%{key: "list", operator: "==", value: list_id}],
           range: [start_idx, start_idx + per_page],
           keys: ["title", "id", "director", "country", "year", "language", "duration"],
           sort: [%{key: "title", operator: "+"}],
           current_user: Keyword.get(opts, :current_user)
         ) do
      {:ok, %{items: items, has_more: has_more}} ->
        {:ok, %{items: items, total: length(items), has_more: has_more}}

      {:ok, %{items: items}} ->
        {:ok, %{items: items, total: length(items), has_more: length(items) >= per_page}}

      other ->
        other
    end
  end
end
