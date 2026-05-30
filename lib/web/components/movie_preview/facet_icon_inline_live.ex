defmodule Bonfire.PanDoRa.Components.FacetIconInlineLive do
  @moduledoc """
  Renders an Iconify icon by name at runtime (`mode={:inline}`) so dynamic facet
  icons work without a precompiled CSS entry in `icons.css`.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop iconify, :string, default: "carbon:information"
  prop class, :string, default: "w-3.5 h-3.5 shrink-0 opacity-80"
end
