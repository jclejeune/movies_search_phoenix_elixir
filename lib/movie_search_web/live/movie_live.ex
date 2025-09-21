defmodule MovieSearchWeb.MovieLive do
  use MovieSearchWeb, :live_view
  alias MovieSearch.Movies

  @items_per_page 3

  @impl true
  def mount(_params, _session, socket) do
    movies = Movies.load_movies()

    socket =
      socket
      |> assign(:all_movies, movies)
      |> assign(:filtered_movies, movies)  # Films après filtres mais avant pagination
      |> assign(:movies, [])  # Films de la page courante
      |> assign(:search_query, "")
      |> assign(:selected_genre, "")
      |> assign(:min_rating, 0)
      |> assign(:sort_by, "title")
      |> assign(:genres, Movies.get_all_genres(movies))
      |> assign(:imdb_loading, false)
      |> assign(:imdb_progress, 0)
      |> assign(:form_mode, :closed)
      |> assign(:editing_movie, nil)
      |> assign(:form_errors, [])
      # Pagination
      |> assign(:current_page, 1)
      |> assign(:items_per_page, @items_per_page)
      |> assign(:total_pages, 1)
      |> assign(:total_items, length(movies))
      |> update_movies()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:current_page, 1)  # Reset à la page 1
      |> update_movies()

    {:noreply, socket}
  end

  def handle_event("filter_genre", %{"genre" => genre}, socket) do
    socket =
      socket
      |> assign(:selected_genre, genre)
      |> assign(:current_page, 1)  # Reset à la page 1
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
      |> assign(:current_page, 1)  # Reset à la page 1
      |> update_movies()

    {:noreply, socket}
  end

  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:current_page, 1)  # Reset à la page 1
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
      |> assign(:current_page, 1)
      |> update_movies()

    {:noreply, socket}
  end

  # Gestion de la pagination
  def handle_event("goto_page", %{"page" => page_str}, socket) do
    case Integer.parse(page_str) do
      {page, _} when page >= 1 and page <= socket.assigns.total_pages ->
        socket =
          socket
          |> assign(:current_page, page)
          |> update_pagination()

        {:noreply, socket}
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("prev_page", _, socket) do
    current_page = socket.assigns.current_page
    if current_page > 1 do
      socket =
        socket
        |> assign(:current_page, current_page - 1)
        |> update_pagination()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("next_page", _, socket) do
    current_page = socket.assigns.current_page
    total_pages = socket.assigns.total_pages

    if current_page < total_pages do
      socket =
        socket
        |> assign(:current_page, current_page + 1)
        |> update_pagination()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
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
          progress = round((index + 1) / total * 100)
          send(pid, {:imdb_progress, progress})

          if needs_repair?(movie) do
            Process.sleep(800)
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

    # Si on supprime le dernier film de la page et qu'on n'est pas sur la page 1
    current_page = socket.assigns.current_page
    filtered_count = length(apply_filters(updated_movies, socket.assigns))
    total_pages = calculate_total_pages(filtered_count, @items_per_page)

    new_current_page = if current_page > total_pages and total_pages > 0 do
      total_pages
    else
      current_page
    end

    {:noreply,
     socket
     |> assign(:all_movies, updated_movies)
     |> assign(:genres, Movies.get_all_genres(updated_movies))
     |> assign(:current_page, new_current_page)
     |> update_movies()}
  end

  def handle_event("first_page", _, socket) do
    if socket.assigns.current_page > 1 do
      socket =
        socket
        |> assign(:current_page, 1)
        |> update_pagination()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("last_page", _, socket) do
    total_pages = socket.assigns.total_pages
    current_page = socket.assigns.current_page

    if current_page < total_pages do
      socket =
        socket
        |> assign(:current_page, total_pages)
        |> update_pagination()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

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
    Movies.save_movies(enriched_movies)

    socket =
      socket
      |> assign(:all_movies, enriched_movies)
      |> assign(:imdb_loading, false)
      |> assign(:imdb_progress, 100)
      |> update_movies()

    {:noreply, socket}
  end

  # Fonction pour appliquer les filtres sans pagination
  defp apply_filters(movies, assigns) do
    %{
      search_query: search_query,
      selected_genre: selected_genre,
      min_rating: min_rating,
      sort_by: sort_by
    } = assigns

    movies
    |> Movies.search_movies(search_query)
    |> Movies.filter_by_genre(selected_genre)
    |> Movies.filter_by_rating(min_rating)
    |> Movies.sort_movies(sort_by)
  end

  # Fonction pour calculer la pagination
  defp paginate(movies, current_page, items_per_page) do
    start_index = (current_page - 1) * items_per_page
    Enum.slice(movies, start_index, items_per_page)
  end

  defp calculate_total_pages(total_items, _items_per_page) when total_items == 0, do: 1
  defp calculate_total_pages(total_items, items_per_page) do
    ceil(total_items / items_per_page)
  end

  # Fonction privée pour mettre à jour les films avec pagination complète
  defp update_movies(socket) do
    filtered_movies = apply_filters(socket.assigns.all_movies, socket.assigns)
    total_items = length(filtered_movies)
    total_pages = calculate_total_pages(total_items, @items_per_page)

    # Ajuster la page courante si nécessaire
    current_page = socket.assigns.current_page
    adjusted_current_page = if current_page > total_pages and total_pages > 0 do
      total_pages
    else
      current_page
    end

    movies = paginate(filtered_movies, adjusted_current_page, @items_per_page)

    socket
    |> assign(:filtered_movies, filtered_movies)
    |> assign(:movies, movies)
    |> assign(:total_items, total_items)
    |> assign(:total_pages, total_pages)
    |> assign(:current_page, adjusted_current_page)
  end

  # Fonction pour mettre à jour seulement la pagination (sans recalculer les filtres)
  defp update_pagination(socket) do
    movies = paginate(socket.assigns.filtered_movies, socket.assigns.current_page, @items_per_page)
    assign(socket, :movies, movies)
  end

  # Fonctions utilitaires
  def format_duration(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)
    "#{hours}h #{mins}min"
  end

  def format_genres(genres) do
    Enum.join(genres, ", ")
  end

  # Helpers pour le template
  def form_open?(form_mode), do: form_mode != :closed
  def form_is_add?(form_mode), do: form_mode == :add
  def form_is_edit?(form_mode), do: form_mode == :edit
  def has_errors?(errors) when is_list(errors), do: length(errors) > 0
  def has_errors?(_), do: false

  # Helpers pour la pagination
  def has_prev_page?(current_page), do: current_page > 1
  def has_next_page?(current_page, total_pages), do: current_page < total_pages

  def page_range(current_page, total_pages) do
    start_page = max(1, current_page - 2)
    end_page = min(total_pages, current_page + 2)
    start_page..end_page
  end

  def start_item_number(current_page, items_per_page) do
    (current_page - 1) * items_per_page + 1
  end

  def end_item_number(current_page, items_per_page, total_items) do
    min(current_page * items_per_page, total_items)
  end

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
