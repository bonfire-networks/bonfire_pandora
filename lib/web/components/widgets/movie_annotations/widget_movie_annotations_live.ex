defmodule Bonfire.PanDoRa.Web.WidgetMovieAnnotationsLive do
  @moduledoc """
  Sidebar widget that renders the **Public annotations** for the current movie inside a
  `<details>` accordion (closed by default).

  This component is intentionally **dumb**: form events
  (`add_annotation`, `update_annotation`, `delete_annotation`, `validate_note`,
  `cancel_edit`, `edit_annotation`) are not targeted on `@myself`, so Phoenix
  forwards them to the parent `Bonfire.PanDoRa.Web.MovieLive`, where the existing
  `handle_event/3` clauses remain the single source of truth for annotation state.
  """

  use Bonfire.UI.Common.Web, :stateful_component

  prop movie, :any, default: nil
  prop public_notes, :list, default: []
  prop note_content, :string, default: ""
  prop in_timestamp, :any, default: nil
  prop out_timestamp, :any, default: nil
  prop editing_mode, :boolean, default: false
  prop editing_annotation, :any, default: nil

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end
end
