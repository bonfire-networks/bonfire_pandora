defmodule Bonfire.PanDoRa.Components.SidebarPandoraLive do
  use Bonfire.UI.Common.Web, :stateful_component

  declare_nav_component("Links to user's groups (and optionally topics)", exclude_from_nav: false)
end
