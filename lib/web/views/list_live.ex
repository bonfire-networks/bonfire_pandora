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
      |> assign(:nav_items, Bonfire.Common.ExtensionModule.default_nav())
      |> assign(:back, true)
      |> assign(:list_id, list_id)
      |> assign(:page, 0)
      |> assign(:per_page, @default_per_page)
      |> assign(:has_more_items, false)
      |> assign(:loading, true)
      |> assign(:error, nil)

    if connected?(socket) do
      send(self(), :load_initial_data)
      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  def handle_info(:load_initial_data, socket) do
    %{list_id: list_id} = socket.assigns

    list_result = fetch_list(list_id)
    items_result = fetch_list_items(list_id)

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
  defp fetch_list(id) do
    Client.get_list(id)
  end

  # Fetch items for a specific list
  defp fetch_list_items(list_id, opts \\ []) do
    Client.find_list_items(list_id, opts)
  end
end
