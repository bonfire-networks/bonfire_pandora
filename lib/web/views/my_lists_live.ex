defmodule Bonfire.PanDoRa.Web.MyListsLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias PanDoRa.API.Client

  @behaviour Bonfire.UI.Common.LiveHandler

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    debug("Mounting MyListsLive")

    # current_user = current_user(assigns(socket))

    # Fetch lists immediately in mount
    lists_result = fetch_my_lists()

    socket =
      socket
      |> assign(:nav_items, Bonfire.Common.ExtensionModule.default_nav())
      |> assign(:back, true)
      |> assign(:page_title, "My lists")
      |> assign(:page_header_aside, [
        {Bonfire.PanDoRa.Components.CreateNewListLive, []}
      ])
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
    IO.inspect(error, label: "Error fetching lists")

    socket
    |> assign(:lists, [])
    |> assign(:loading, false)
    |> assign(:error, error)
  end

  # Fetch lists for the current user
  defp fetch_my_lists() do
    Client.find_lists(
      keys: ["id", "description", "editable", "name", "status"],
      sort: [%{key: "name", operator: "+"}],
      type: :user
    )
  end

  def handle_event("delete_list", %{"list-id" => id} = _params, socket) do
    debug(id, "delete_list_params")

    case Client.remove_list(id) do
      {:ok, _} ->
        # Remove the list from the UI
        lists = Enum.reject(socket.assigns.lists, &(&1["id"] == id))

        Bonfire.UI.Common.OpenModalLive.close()

        {:noreply,
         socket
         |> assign(:lists, lists)
         |> assign_flash(:info, l("List deleted successfully"))}

      {:error, error} ->
        {:noreply,
         socket
         |> assign_flash(:error, error)}
    end
  end

  def handle_event("validate_update_list", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_list", %{"list" => list_params} = _params, socket) do
    debug(list_params, "update_list_params")

    # Extract the ID and remove it from params to be updated
    id = Map.get(list_params, "id")
    update_params = Map.drop(list_params, ["id"])

    case Client.edit_list(id, update_params) do
      {:ok, updated_list} ->
        # Update the list in the lists array
        lists =
          Enum.map(socket.assigns.lists, fn list ->
            if list["id"] == id, do: updated_list, else: list
          end)

        Bonfire.UI.Common.OpenModalLive.close()

        {:noreply,
         socket
         |> assign(:lists, lists)
         |> assign_flash(:info, l("List updated successfully"))}

      {:error, error} ->
        {:noreply,
         socket
         |> put_flash(:error, error)}
    end
  end

  def handle_event("new_list_create", %{"list" => list_params} = _params, socket) do
    debug(list_params, "new_list_params")

    case Client.add_list(list_params) do
      {:ok, new_list} ->
        # Add the new list to the existing lists
        lists = [new_list | socket.assigns.lists]

        Bonfire.UI.Common.OpenModalLive.close()

        {:noreply,
         socket
         |> assign(:lists, lists)
         |> assign_flash(:info, l("List created successfully"))}

      {:error, error} ->
        {:noreply,
         socket
         |> assign_flash(:error, error)}
    end
  end

  def handle_event("new_list_validate", _params, socket) do
    {:noreply, socket}
  end
end
