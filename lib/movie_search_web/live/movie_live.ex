defmodule MovieSearchWeb.MovieLive do
  use MovieSearchWeb, :live_view
  alias MovieSearch.Movies

  @impl true
  def mount(_params, _session, socket) do
    movies = Movies.load_movies()

    socket =
      socket
      |> assign(:all_movies, movies)
      |> assign(:movies, movies)
      |> assign(:search_query, "")
      |> assign(:selected_genre, "")
      |> assign(:min_rating, 0)
      |> assign(:sort_by, "title")
      |> assign(:genres, Movies.get_all_genres(movies))
      |> assign(:imdb_loading, false)
      |> assign(:imdb_progress, 0)
      |> assign(:form_mode, :closed)  # :closed, :add, :edit
      |> assign(:editing_movie, nil)
      |> assign(:form_errors, [])

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> update_movies()

    {:noreply, socket}
  end

  def handle_event("filter_genre", %{"genre" => genre}, socket) do
    socket =
      socket
      |> assign(:selected_genre, genre)
      |> update_movies()

    {:noreply, socket}
  end

  def handle_event("filter_rating", %{"rating" => rating}, socket) do
    min_rating =
      case Float.parse(rating) do
        {num, _} -> num
        :error -> 0
      end

    socket =
      socket
      |> assign(:min_rating, min_rating)
      |> update_movies()

    {:noreply, socket}
  end

  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> update_movies()

    {:noreply, socket}
  end

  def handle_event("reset_filters", _, socket) do
    socket =
      socket
      |> assign(:search_query, "")
      |> assign(:selected_genre, "")
      |> assign(:min_rating, 0)
      |> assign(:sort_by, "title")
      |> assign(:movies, socket.assigns.all_movies)

    {:noreply, socket}
  end

  def handle_event("check_missing_images", _, socket) do
    socket = assign(socket, :imdb_loading, true)

    pid = self()
    spawn(fn ->
      total = length(socket.assigns.all_movies)

      repaired_movies =
        socket.assigns.all_movies
        |> Enum.with_index()
        |> Enum.map(fn {movie, index} ->
          # Progress
          progress = round((index + 1) / total * 100)
          send(pid, {:imdb_progress, progress})

          # Vérifie et répare si nécessaire
          if needs_repair?(movie) do
            Process.sleep(800)  # Rate limiting
            Movies.enrich_with_imdb(movie)
          else
            movie
          end
        end)

      send(pid, {:imdb_complete, repaired_movies})
    end)

    {:noreply, socket}
  end

  def handle_event("show_add_form", _, socket) do
    {:noreply,
     socket
     |> assign(:form_mode, :add)
     |> assign(:editing_movie, nil)
     |> assign(:form_errors, [])
     |> push_event("scroll_to_form", %{})}
  end

  def handle_event("show_edit_form", %{"id" => id}, socket) do
    movie = Enum.find(socket.assigns.all_movies, &(&1.id == String.to_integer(id)))

    {:noreply,
     socket
     |> assign(:form_mode, :edit)
     |> assign(:editing_movie, movie)
     |> assign(:form_errors, [])
     |> push_event("scroll_to_form", %{})}
  end

  def handle_event("close_form", _, socket) do
    {:noreply,
     socket
     |> assign(:form_mode, :closed)
     |> assign(:editing_movie, nil)
     |> assign(:form_errors, [])}
  end

  def handle_event("add_movie", %{"movie" => movie_params}, socket) do
    case validate_movie_params(movie_params) do
      [] ->
        # Validation OK
        case Movies.add_movie(socket.assigns.all_movies, movie_params) do
          {:ok, updated_movies, _new_movie} ->
            socket =
              socket
              |> assign(:all_movies, updated_movies)
              |> assign(:genres, Movies.get_all_genres(updated_movies))
              |> assign(:form_mode, :closed)
              |> assign(:form_errors, [])
              |> update_movies()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, assign(socket, :form_errors, ["Erreur lors de l'ajout: #{inspect(reason)}"])}
        end

      errors ->
        # Validation failed
        {:noreply, assign(socket, :form_errors, errors)}
    end
  end

  def handle_event("update_movie", %{"movie" => params}, socket) do
    case validate_movie_params(params) do
      [] ->
        movie = socket.assigns.editing_movie
        movies = socket.assigns.all_movies

        updated_movie = %Movies{
          movie |
          title: params["title"],
          year: String.to_integer(params["year"]),
          genre: String.split(params["genre"], ",") |> Enum.map(&String.trim/1),
          director: params["director"],
          rating: String.to_float(params["rating"]),
          duration: String.to_integer(params["duration"]),
          description: params["description"]
        }

        updated_movies = Enum.map(movies, fn m ->
          if m.id == updated_movie.id, do: updated_movie, else: m
        end)

        Movies.save_movies(updated_movies)

        {:noreply,
         socket
         |> assign(:all_movies, updated_movies)
         |> assign(:form_mode, :closed)
         |> assign(:editing_movie, nil)
         |> assign(:form_errors, [])
         |> update_movies()}

      errors ->
        {:noreply, assign(socket, :form_errors, errors)}
    end
  end

  def handle_event("delete_movie", %{"id" => id}, socket) do
    id = String.to_integer(id)
    updated_movies = Enum.reject(socket.assigns.all_movies, &(&1.id == id))
    Movies.save_movies(updated_movies)

    {:noreply,
     socket
     |> assign(:all_movies, updated_movies)
     |> assign(:genres, Movies.get_all_genres(updated_movies))
     |> update_movies()}
  end

  # Fonction helper pour détecter si une réparation est nécessaire
  defp needs_repair?(%Movies{poster: poster}) do
    cond do
      String.starts_with?(poster, "/images/posters/") ->
        not File.exists?("priv/static#{poster}")
      String.contains?(poster, "picsum.photos") ->
        true
      true ->
        false
    end
  end

  @impl true
  def handle_info({:imdb_progress, progress}, socket) do
    {:noreply, assign(socket, :imdb_progress, progress)}
  end

  def handle_info({:imdb_complete, enriched_movies}, socket) do
    # Sauvegarde les films avec les nouvelles images
    Movies.save_movies(enriched_movies)

    socket =
      socket
      |> assign(:all_movies, enriched_movies)
      |> assign(:imdb_loading, false)
      |> assign(:imdb_progress, 100)
      |> update_movies()

    {:noreply, socket}
  end

  # Fonction privée pour mettre à jour la liste des films affichés
  defp update_movies(socket) do
    %{
      all_movies: all_movies,
      search_query: search_query,
      selected_genre: selected_genre,
      min_rating: min_rating,
      sort_by: sort_by
    } = socket.assigns

    movies =
      all_movies
      |> Movies.search_movies(search_query)
      |> Movies.filter_by_genre(selected_genre)
      |> Movies.filter_by_rating(min_rating)
      |> Movies.sort_movies(sort_by)

    assign(socket, :movies, movies)
  end

  # Fonction utilitaire pour formater la durée
  def format_duration(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)
    "#{hours}h #{mins}min"
  end

  # Fonction utilitaire pour formater les genres
  def format_genres(genres) do
    Enum.join(genres, ", ")
  end

  # Helpers pour le template
  def form_open?(form_mode), do: form_mode != :closed
  def form_is_add?(form_mode), do: form_mode == :add
  def form_is_edit?(form_mode), do: form_mode == :edit
  def has_errors?(errors) when is_list(errors), do: length(errors) > 0
  def has_errors?(_), do: false

  # Validation helper
  defp validate_movie_params(params) do
    errors = []

    errors = if blank?(params["title"]), do: errors ++ ["Titre requis"], else: errors
    errors = if blank?(params["director"]), do: errors ++ ["Réalisateur requis"], else: errors
    errors = if blank?(params["year"]), do: errors ++ ["Année requise"], else: errors
    errors = if blank?(params["genre"]), do: errors ++ ["Genre requis"], else: errors
    errors = if blank?(params["rating"]), do: errors ++ ["Note requise"], else: errors
    errors = if blank?(params["duration"]), do: errors ++ ["Durée requise"], else: errors

    # Validation des types
    errors =
      if not blank?(params["year"]) do
        case Integer.parse(params["year"]) do
          {year, _} when year >= 1900 and year <= 2030 -> errors
          _ -> errors ++ ["Année invalide (1900-2030)"]
        end
      else
        errors
      end

    errors =
      if not blank?(params["rating"]) do
        case Float.parse(params["rating"]) do
          {rating, _} when rating >= 0.0 and rating <= 10.0 -> errors
          _ -> errors ++ ["Note invalide (0.0-10.0)"]
        end
      else
        errors
      end

    errors =
      if not blank?(params["duration"]) do
        case Integer.parse(params["duration"]) do
          {duration, _} when duration > 0 -> errors
          _ -> errors ++ ["Durée invalide (>0)"]
        end
      else
        errors
      end

    errors
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(str) when is_binary(str), do: String.trim(str) == ""
  defp blank?(_), do: false
end
