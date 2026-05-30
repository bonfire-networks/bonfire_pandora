defmodule Bonfire.PanDoRa.Components.ArchiveIconButtonLive do
  @moduledoc """
  Icon-only button for standalone archive controls (filter chip dismiss, etc.).
  Styled to match Bonfire design-system tiers using shared PanDoRa token helpers.

  Do **not** use inside `OpenModalLive`'s `open_btn` slot: that wrapper is already a
  `<button>` — nest a plain `<#Icon>` or `<div class="btn …">` instead.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop icon, :string, required: true
  prop aria_label, :string, required: true
  prop size, :string, default: "sm", values: ["xs", "sm"]
  prop phx_click, :any, default: nil
  prop phx_target, :any, default: nil
  prop phx_value_field, :string, default: nil
  prop phx_value_id, :string, default: nil
  prop disabled, :boolean, default: false
  prop tooltip, :string, default: nil
  prop class, :any, default: nil
  prop id, :string, default: nil
end
