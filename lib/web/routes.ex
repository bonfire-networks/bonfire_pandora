defmodule Bonfire.PanDoRa.Web.Routes do
  use Bonfire.Common.Localise
  import Bonfire.Common.Modularity.DeclareHelpers
  import Bonfire.UI.Common.Modularity.DeclareHelpers

  @behaviour Bonfire.UI.Common.RoutesModule

  defmacro __using__(_) do
    quote do
      # pages anyone can view
      scope "/pandora/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)

        live("/", SearchLive)
      end

      # pages only guests can view
      scope "/pandora/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)
        pipe_through(:guest_only)
      end

      # pages you need an account to view
      scope "/pandora/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)
        pipe_through(:account_required)
      end

      # pages you need to view as a user
      scope "/pandora/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)
        pipe_through(:user_required)
      end

      # pages only admins can view
      scope "/pandora/admin", Bonfire.PanDoRa.Web do
        pipe_through(:browser)
        pipe_through(:admin_required)
      end
    end
  end
end
