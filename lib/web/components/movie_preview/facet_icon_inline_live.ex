defmodule Bonfire.PanDoRa.Components.FacetIconInlineLive do
  @moduledoc """
  Renders an Iconify icon by name at runtime. Do not use `<#Icon iconify={...}>` here: that macro
  only accepts static `iconify` literals, not assigns.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop iconify, :string, default: "carbon:information"
  prop class, :string, default: "w-3.5 h-3.5 shrink-0 opacity-80"
end
