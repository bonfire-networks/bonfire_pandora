defmodule Bonfire.PanDoRa.Components.GlobeIconLive do
  @moduledoc """
  Inline SVG globe (Heroicons outline) — does not depend on Iconify bundles.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop class, :string, default: "w-3 h-3 shrink-0 opacity-80"
end
