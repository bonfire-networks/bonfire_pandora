defmodule Bonfire.PanDoRa.Web.UI do
  @moduledoc """
  Shared UI design tokens (CSS class strings) for the PanDoRa archive UI.

  Centralizes recurring DaisyUI/Tailwind class combinations so the Search,
  Movie and list surfaces stop diverging into slightly different copy-pasted
  variants. Pure functions returning class strings, safe to call directly from
  `.sface` templates (e.g. `class={Bonfire.PanDoRa.Web.UI.player_divider()}`).
  """

  @doc """
  Base classes for an icon-only control button in the Movie player action bar.

  Kept as a hand-rolled DaisyUI button (rather than the design-system
  `<.icon_button>`) because the action bar is a dense toolbar: the design-system
  button adds an invisible `touch-target-expanded` hit area that would overlap
  with adjacent controls, and the player JS hook relies on `data-action` plus
  toggle icons that the icon-only component does not model.

  ## Examples

      iex> Bonfire.PanDoRa.Web.UI.player_control_button()
      "btn btn-sm btn-circle btn-soft btn-ghost min-h-8 h-8"
  """
  def player_control_button, do: "btn btn-sm btn-circle btn-soft btn-ghost min-h-8 h-8"

  @doc """
  Vertical separator between control groups in the Movie player action bar.

  ## Examples

      iex> Bonfire.PanDoRa.Web.UI.player_divider()
      "w-px h-6 bg-base-content/20 mx-1 self-center"
  """
  def player_divider, do: "w-px h-6 bg-base-content/20 mx-1 self-center"

  @doc """
  Classes for a facet link chip in the Movie Info widget. `variant` is the
  DaisyUI semantic suffix tying the chip to its facet family (`neutral` for
  metadata, `success` for featuring, `accent` for keywords).

  Reuses `Bonfire.PanDoRa.Utils.facet_btn_base/0` so Movie Info chips and Search
  card chips share one definition and can't drift apart.

  ## Examples

      iex> Bonfire.PanDoRa.Web.UI.facet_link("accent") == "\#{Bonfire.PanDoRa.Utils.facet_btn_base()} btn-accent"
      true
  """
  def facet_link(variant) when variant in ~w(neutral success accent),
    do: "#{Bonfire.PanDoRa.Utils.facet_btn_base()} btn-#{variant}"
end
