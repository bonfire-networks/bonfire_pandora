defmodule Bonfire.PanDoRa.Web.SearchLive do
  @moduledoc """
  Thin **LiveComponent** wrapper for backward compatibility.

  Older templates (e.g. federated dashboard) still mount `SearchLive` via
  `StatefulComponent` / `live_component`, which requires `__live__/0`.
  The real markup lives in `ArchiveSearchPanel` (stateless).

  New code should use `ArchiveSearchPanel` directly on the parent LiveView.

  ## Deploy note

  If you still see `SearchLive.__live__/0` undefined at runtime, the running BEAM
  is not this module: ensure `config/deps.path` points `bonfire_pandora` at your
  extension checkout, then run `rm -rf _build && mix deps.compile bonfire_pandora --force`
  (or bump this app’s version in `mix.lock` after pull). Do not rely on a stale
  `deps/bonfire_pandora` copy if `extensions/bonfire_pandora` is gitignored in the app repo.
  """
  use Bonfire.UI.Common.Web, :stateful_component

  alias PanDoRa.API.Client

  prop term, :string
  prop current_user, :any
  prop effective_api_keys, :map, default: %{}
  prop filter_sections, :list, default: []
  prop active_filter_badges, :list, default: []
  prop selected_by_field, :map, default: %{}
  prop loading, :boolean, default: false
  prop page, :integer, default: 0
  prop has_more_items, :boolean, default: true
  prop current_count, :integer, default: 0
  prop pandora_token, :string, default: nil
  prop pandora_base_url, :string, default: nil

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @doc false
  def show_filter_bar?(nil, badges), do: has_active_filters?(badges)
  def show_filter_bar?("", badges), do: has_active_filters?(badges)

  def show_filter_bar?(term, badges) when is_binary(term) do
    String.trim(term) != "" or has_active_filters?(badges)
  end

  def show_filter_bar?(_, badges), do: has_active_filters?(badges)

  defp has_active_filters?([]), do: false

  defp has_active_filters?(badges) when is_list(badges) do
    Enum.any?(badges, fn %{values: v} -> length(List.wrap(v)) > 0 end)
  end

  defp has_active_filters?(_), do: false

  @doc false
  def term_chip?(nil), do: false
  def term_chip?(""), do: false

  def term_chip?(term) when is_binary(term), do: String.trim(term) != ""
  def term_chip?(_), do: false

  @doc false
  def term_chip_text(term) when is_binary(term) do
    t = String.trim(term)
    slice = String.slice(t, 0, 30)
    if String.length(t) > 30, do: slice <> "...", else: slice
  end

  def term_chip_text(_), do: ""

  @doc false
  def filter_field_api_key_for_badge(%{id: type}, effective_api_keys)
      when is_map(effective_api_keys) do
    t = to_string(type)

    Map.get(effective_api_keys, type) || Map.get(effective_api_keys, t) ||
      Client.filter_type_to_api_key(t)
  end

  def filter_field_api_key_for_badge(%{id: type}, _) do
    Client.filter_type_to_api_key(to_string(type))
  end

  @doc false
  def filter_badge_value_attr(v), do: Bonfire.PanDoRa.Utils.to_attr(v)
end
