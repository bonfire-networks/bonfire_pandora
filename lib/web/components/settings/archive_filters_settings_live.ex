defmodule Bonfire.PanDoRa.Web.ArchiveFiltersSettingsLive do
  @moduledoc """
  Instance settings UI for the /archive sidebar filters (same extension page as Sync Pandora).

  Persists `[:ui, :archive_search_filters, …]` via `Bonfire.Common.Settings` (`scope: :instance`).
  """
  use Bonfire.UI.Common.Web, :stateful_component
  use Bonfire.Common.Localise

  alias Bonfire.Common.Settings

  declare_settings_component(l("Archive sidebar filters"),
    icon: "ph:faders-horizontal",
    description:
      l(
        "Layout of the filter column on /archive: list height, card style, title style. Instance-wide."
      ),
    scope: :instance
  )

  prop scope, :any, default: nil

  def update(assigns, socket) do
    scope = assigns[:scope]
    ctx = assigns[:__context__] || socket.assigns[:__context__]
    user = current_user_from(assigns, socket)

    scoped_opts =
      if scope == :instance do
        [scope: :instance, current_user: user]
      else
        [current_user: user]
      end

    socket =
      socket
      |> assign(assigns)
      |> assign(:scoped_opts, scoped_opts)
      |> assign(:can_edit?, scope == :instance && instance_admin?(ctx))
      |> assign(
        :list_height_px,
        Settings.get([:ui, :archive_search_filters, :list_height_px], 140, scoped_opts)
      )
      |> assign(
        :title_style,
        style_for_form(
          Settings.get([:ui, :archive_search_filters, :title_style], "compact", scoped_opts),
          ~w(compact prominent),
          "compact"
        )
      )
      |> assign(
        :card_style,
        style_for_form(
          Settings.get([:ui, :archive_search_filters, :card_style], "transparent", scoped_opts),
          ~w(transparent card),
          "transparent"
        )
      )
      |> assign(
        :filters_disabled?,
        Settings.get([:ui, :archive_search_filters, :disabled], nil, scoped_opts) == true
      )

    {:ok, socket}
  end

  def handle_event("save_archive_filters", params, socket) do
    if not socket.assigns[:can_edit?] do
      {:noreply, Bonfire.UI.Common.assign_flash(socket, :error, l("Insufficient permissions"))}
    else
      user = current_user_from(socket.assigns, socket)

      list_height =
        case Integer.parse(to_string(params["list_height_px"] || "140")) do
          {n, _} -> min(max(n, 40), 2000)
          _ -> 140
        end

      title_style = normalize_select(params["title_style"], ~w(compact prominent), "compact")
      card_style = normalize_select(params["card_style"], ~w(transparent card), "transparent")
      disabled = params["filters_disabled"] in ["true", "on", "1"]

      opts = [scope: :instance, current_user: user]

      with {:ok, _} <-
             Settings.put([:ui, :archive_search_filters, :list_height_px], list_height, opts),
           {:ok, _} <-
             Settings.put([:ui, :archive_search_filters, :title_style], title_style, opts),
           {:ok, _} <- Settings.put([:ui, :archive_search_filters, :card_style], card_style, opts),
           {:ok, _} <-
             Settings.put(
               [:ui, :archive_search_filters, :disabled],
               if(disabled, do: true, else: nil),
               opts
             ) do
        {:noreply,
         socket
         |> Bonfire.UI.Common.assign_flash(:info, l("Archive filter settings saved"))
         |> assign(:list_height_px, list_height)
         |> assign(:title_style, title_style)
         |> assign(:card_style, card_style)
         |> assign(:filters_disabled?, disabled)}
      else
        _ ->
          {:noreply, Bonfire.UI.Common.assign_flash(socket, :error, l("Could not save settings"))}
      end
    end
  end

  defp instance_admin?(context) when not is_nil(context) do
    Bonfire.Boundaries.can?(context, :configure, :instance) == true
  end

  defp instance_admin?(_), do: false

  defp current_user_from(assigns, socket) do
    assigns[:current_user] ||
      Map.get(assigns[:__context__] || socket.assigns[:__context__] || %{}, :current_user)
  end

  defp normalize_select(value, allowed, default) do
    v = value |> to_string() |> String.trim() |> String.downcase()
    if v in allowed, do: v, else: default
  end

  defp style_for_form(raw, allowed, default) do
    v =
      cond do
        is_nil(raw) ->
          default

        is_atom(raw) ->
          raw |> Atom.to_string() |> String.trim() |> String.downcase()

        is_binary(raw) ->
          raw |> String.trim() |> String.downcase()

        true ->
          default
      end

    if v in allowed, do: v, else: default
  end
end
