defmodule Bonfire.PanDoRa.Web.Routes do
  use Bonfire.Common.Localise
  import Bonfire.Common.Modularity.DeclareHelpers
  import Bonfire.UI.Common.Modularity.DeclareHelpers

  @behaviour Bonfire.UI.Common.RoutesModule

  defmacro __using__(_) do
    quote do
      # pages anyone can view
      scope "/archive/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)

        live("/", SearchViewLive)
      end

      # pages only guests can view
      scope "/archive/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)
        pipe_through(:guest_only)
      end

      # pages you need an account to view
      scope "/archive/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)
        pipe_through(:account_required)
      end

      # pages you need to view as a user
      scope "/archive/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)
        pipe_through(:user_required)

        live("/movies/:id", MovieLive)
        live("/my_lists/", MyListsLive)
        live("/featured_lists/", FeaturedListsLive)
        live("/lists/:id", ListLive)
      end

      # pages only admins can view
      scope "/archive/admin", Bonfire.PanDoRa.Web do
        pipe_through(:browser)
        pipe_through(:admin_required)
      end
    end
  end
end
