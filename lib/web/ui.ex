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
  Wrapper for the Movie custom action bar — single row, three zones (Tailwind flex, no wrap).
  """
  def player_action_bar,
    do:
      "custom-action-bar mt-2 flex h-8 min-h-8 w-full min-w-0 max-w-full flex-nowrap items-center gap-2 sm:gap-3"

  @doc """
  Left zone: transport + IN/OUT (anchored start).
  """
  def player_action_bar_left,
    do: "flex shrink-0 flex-nowrap items-center gap-1 sm:gap-1.5"

  @doc """
  Center zone: timecode (flex-1, truncated if tight).
  """
  def player_action_bar_center,
    do: "flex min-w-0 flex-1 basis-0 items-center justify-center overflow-hidden px-0.5 sm:px-1"

  @doc """
  Right zone: volume, speed, fullscreen (anchored end).
  """
  def player_action_bar_right,
    do: "flex shrink-0 flex-nowrap items-center gap-1 sm:gap-1.5"

  @doc """
  Default inline cluster inside left/right zones (transport icons, etc.).
  """
  def player_action_bar_group, do: "flex shrink-0 items-center gap-1.5"

  @doc "Deprecated alias — use `player_action_bar_center/0`."
  def player_action_bar_timecode_group, do: player_action_bar_center()

  @doc "Deprecated alias — use `player_action_bar_right/0`."
  def player_action_bar_output_group, do: player_action_bar_right()

  @doc """
  Timecode readout in the Movie action bar (monospaced, same vertical band as h-8 controls).
  """
  def player_timecode,
    do:
      "font-mono text-[11px] sm:text-sm tabular-nums text-base-content/80 select-none flex items-center h-8 leading-none tracking-tight whitespace-nowrap truncate max-w-full"

  @doc """
  Mute button + volume range grouped in the Movie action bar output cluster.
  """
  def player_volume_group, do: "flex shrink-0 items-center gap-1"

  @doc """
  Compact volume slider for the Movie custom action bar (pairs with toggle-mute).

  Plain native range — no DaisyUI `.range` (avoids oversized pill control).
  """
  def player_volume_slider, do: "player-volume-slider"

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

  @doc """
  Outer row for an archive search result card.

  ## Examples

      iex> String.contains?(Bonfire.PanDoRa.Web.UI.archive_card_row(), "border-b")
      true
  """
  def archive_card_row,
    do:
      "group flex gap-4 p-4 border-b border-base-content/10 min-w-0 transition-colors duration-150 hover:bg-base-200/30"

  @doc "Thumbnail image classes for archive search cards."
  def archive_card_thumb,
    do: "block h-20 w-[7rem] rounded-lg object-cover ring-1 ring-base-content/10 shadow-sm"

  @doc "Interactive meta chip (country/year) in the card header."
  def meta_chip_button,
    do:
      "btn btn-xs btn-ghost inline-flex h-6 min-h-0 max-w-[9rem] items-center gap-1 px-1.5 py-0 text-xs font-normal leading-none text-base-content/60 hover:text-base-content"

  @doc "Static meta label (duration or filter links off)."
  def meta_chip_static,
    do:
      "inline-flex h-6 max-w-[9rem] items-center gap-1 text-xs font-normal leading-none text-base-content/60"

  @doc "Timeline expand control beside the strip (not design-system: needs data-role for hook)."
  def timeline_expand_button,
    do: "btn btn-sm btn-circle btn-ghost shrink-0 self-center min-h-8 h-8 opacity-70 hover:opacity-100"

  @doc """
  Circle icon-only button for standalone archive actions (chip dismiss, bookmark, edit).

  Matches design-system sizing tiers without wrapping `IconButtonLive` (Phoenix
  function component — not renderable as a Surface tag).
  """
  def icon_button_classes("xs"),
    do: "btn btn-xs btn-circle btn-ghost min-h-0 h-5 w-5 p-0"

  def icon_button_classes("sm"), do: "btn btn-sm btn-circle btn-ghost"
  def icon_button_classes(_), do: "btn btn-sm btn-circle btn-ghost"

  def icon_button_icon_classes("xs"), do: "w-3.5 h-3.5"
  def icon_button_icon_classes(_), do: "w-4 h-4"
end
