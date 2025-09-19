defmodule MovieSearchWeb.PageController do
  use MovieSearchWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
