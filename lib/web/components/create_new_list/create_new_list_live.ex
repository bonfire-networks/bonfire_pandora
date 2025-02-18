defmodule Bonfire.PanDoRa.Components.CreateNewListLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias PanDoRa.API.Client
  alias Bonfire.Files.IconUploader

  prop uploaded_files, :any, default: nil
  prop src, :string, default: nil

  def update(assigns, socket) do
    debug(assigns, "Initializing CreateNewListLive")
    {:ok,
     socket
     |> assign(assigns)}
  end

  def handle_event("new_list_create", %{"list" => list_params}, socket) do
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

    handle_create_list(list_params, socket)
  end

  def handle_info({:update_list_icon, media} = msg, socket) do
    IO.inspect(media, label: "Received list icon update")
    {:noreply,
     socket
     |> assign(
       uploaded_files: media
     )}
  end

  def handle_info(msg, socket) do
    IO.inspect(msg, label: "Received message")
    {:noreply, socket}
  end

  def set_list_icon(:icon, :pandora_list, %Bonfire.Files.Media{} = media, assign_field, socket) do
    # Store the uploaded media for use in list creation
    IO.inspect(media, label: "Setting list icon")

    # Send message to parent component using standard send
    send(self(), {:update_list_icon, media})

    # Only update src in the upload component's socket
    {:noreply,
     socket
     |> assign(
       src: media.path,
       uploaded_files: media
     )}
  end

  defp handle_create_list(list_params, socket) do
    case Client.add_list(list_params) do
      {:ok, new_list} ->
        send(self(), {:list_created, new_list})
        Bonfire.UI.Common.OpenModalLive.close()
        {:noreply, socket |> assign_flash(:info, l("List created successfully"))}

      {:error, error} ->
        {:noreply, socket |> assign_flash(:error, error)}
    end
  end
end
