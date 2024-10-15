defmodule Bonfire.PanDoRa.Web.HomeLive do
  use Bonfire.UI.Common.Web, :surface_live_view


  def mount(_params, _session, socket) do
    {:ok,
     assign(
       socket,
       page: "extension_template",
       page_title: "ExtensionTemplate"
     )}
  end

  def handle_event(
        "custom_event",
        _attrs,
        socket
      ) do
    # handle the event here
    {:noreply, socket}
  end
end
