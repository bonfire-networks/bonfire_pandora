defmodule Bonfire.PanDoRa.Components.FacetChipLive do
  @moduledoc """
  Renders a single archive facet value as a filter chip, read-only badge, or
  archive link. Centralises chip markup so Search cards and Movie Info stay aligned.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.PanDoRa.Utils
  alias Bonfire.PanDoRa.Web.UI

  @modes [:filter, :display, :link]

  prop value, :string, required: true
  prop mode, :atom, default: :filter, values: @modes
  prop variant, :string, default: "neutral", values: ["neutral", "success", "accent"]
  prop field, :string, default: nil
  prop api_key, :string, default: nil
  prop icon, :string, default: nil
  prop icon_class, :string, default: nil
  prop button_class, :string, default: nil
  prop badge_class, :string, default: nil
  prop event_target, :any, default: nil
  prop href, :string, default: nil
  prop phx_click, :string, default: "filter_by_field"
  prop phx_click_director, :boolean, default: false

  @doc "DaisyUI classes for interactive filter chips when `button_class` is not precomputed."
  def filter_button_class(%{button_class: class}) when is_binary(class) and class != "",
    do: class

  def filter_button_class(%{field: field}) when is_binary(field) and field != "",
    do: Utils.filter_field_button_class(field)

  def filter_button_class(%{variant: variant}), do: UI.facet_link(variant)

  def filter_button_class(_), do: UI.facet_link("neutral")

  @doc "DaisyUI classes for read-only facet badges when `badge_class` is not precomputed."
  def filter_badge_class(%{badge_class: class}) when is_binary(class) and class != "",
    do: class

  def filter_badge_class(%{field: field}) when is_binary(field) and field != "",
    do: Utils.filter_field_badge_class(field)

  def filter_badge_class(_), do: Utils.filter_field_badge_class(nil)
end
