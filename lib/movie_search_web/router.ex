# lib/movie_search_web/router.ex
defmodule MovieSearchWeb.Router do
  use MovieSearchWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MovieSearchWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", MovieSearchWeb do
    pipe_through :browser

    live "/", MovieLive, :index
  end
end
