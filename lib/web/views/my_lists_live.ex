defmodule Bonfire.PanDoRa.Web.MyListsLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias PanDoRa.API.Client

  @behaviour Bonfire.UI.Common.LiveHandler

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    # Fetch lists immediately in mount
    lists_result = fetch_my_lists()
    socket =
      socket
      |> assign(:nav_items, Bonfire.Common.ExtensionModule.default_nav())
      |> assign(:back, true)
      |> assign(:page_title, "My lists")
      |> assign(:uploaded_files, nil)
      # |> assign(:page_header_aside, [
      #   {Bonfire.PanDoRa.Components.CreateNewListLive, [id: "create_new_list", myself: @myself]}
      # ])
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
      keys: ["id", "description", "poster_frames", "posterFrames", "editable", "name", "status"],
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
    debug(socket.assigns.uploaded_files, "Uploaded files during list creation")

    list_params =
      case socket.assigns.uploaded_files do
        %Bonfire.Files.Media{} = uploaded_media  ->
          debug(uploaded_media, "Adding icon to list params")
          Map.put(list_params, "posterFrames", [{uploaded_media.path, 0}])
        _ ->
          debug("No icon available")
          list_params
      end
    # Extract the ID and remove it from params to be updated
    id = Map.get(list_params, "id")
    update_params = Map.drop(list_params, ["id"])

    case Client.edit_list(id, update_params) do
      {:ok, updated_list} ->
        # Update the list in the lists array
        lists =
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


  def handle_info({:list_created, new_list}, socket) do
    lists = [new_list | socket.assigns.lists]
    {:noreply, assign(socket, :lists, lists)}
  end

  # WIP: need to move this function to create_new_list component
  def handle_info({:update_list_icon, media} = msg, socket) do
    IO.inspect(media, label: "Received list icon update")
    {:noreply,
     socket
     |> assign(
       uploaded_files: media
     )}
  end

  def handle_info(msg, socket) do
    {:noreply, socket}
  end
end
