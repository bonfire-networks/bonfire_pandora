defmodule Bonfire.PanDoRa.Web.WidgetSearchFiltersLive do
  @moduledoc """
  Sidebar widget for archive search filters (director, year, keywords, etc.).
  Renders filter blocks; events bubble to the parent LiveView (SearchViewLive).
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop filter_sections, :list, default: []
  prop loading, :boolean, default: false
  prop widget_title, :string, default: nil
end
