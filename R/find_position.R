#' Find position
#'
#' @param df track_list of data frames.
#' @param exp_setup Experimental setup, eith "wellplate " or "tube".
#' @param animal_ids Vector of animal IDs, as strings.
#'
#' @import dplyr
#' @importFrom forcats as_factor
#' @importFrom tidyr unite
#' @importFrom graphics hist
#' @importFrom stats na.omit median
#' @return A single tibble
#' @export


find_position <- function(df,
                          exp_setup = c("wellplate", "tube"),
                          animal_ids){

  if (exp_setup == "wellplate") {
    mean_xy <- summarise(df,
                         x_min = min(.data$x_cm),
                         x_max = max(.data$x_cm),
                         x_range = max(.data$x_cm) - min(.data$x_cm),
                         x_center = x_min + x_range / 2,
                         y_min = min(.data$y_cm),
                         y_max = max(.data$y_cm),
                         y_range = max(.data$y_cm) - min(.data$y_cm),
                         y_center = y_min + y_range / 2)

    # Break right
    df_temp <- df %>%
      filter(x_cm > mean_xy$x_center,
             x_cm < mean_xy$x_max)
    x_hist <- graphics::hist(df_temp$x_cm)
    x_min_right <- which.min(x_hist$density)
    break_right <- x_hist$mids[x_min_right]

    # Break left
    df_temp <- df %>%
      filter(x_cm < mean_xy$x_center,
             x_cm > mean_xy$x_min)
    x_hist <- hist(df_temp$x_cm)
    x_min_left <- which.min(x_hist$density)
    break_left <- x_hist$mids[x_min_left]

    # Break vertical
    df_temp <- df %>%
      filter(y_cm < mean_xy$y_max - 1,
             y_cm > mean_xy$y_min + 1)
    y_hist <- hist(df_temp$y_cm)
    y_min <- which.min(y_hist$density)
    break_y <- y_hist$mids[y_min]

    df <- df %>%
      filter(!.data$x_cm %in% c(break_left, break_right) &
               .data$y_cm != break_y) %>% # Make sure there's no observations right on the thresholds
      mutate(height = if_else(.data$y_cm > break_y, "top", "bottom"),
             length = case_when(.data$x_cm < break_left ~ "left",
                                .data$x_cm > break_right ~ "right",
                                .data$x_cm > break_left & .data$x_cm < break_right ~ "middle")) %>%
      arrange(desc(.data$height), .data$length) %>%
      unite("position", .data$height:.data$length, remove=TRUE)

    # Do the rest of the fiddling
    positions <- unique(df$position)
    positions <- stats::na.omit(positions)
    new_animal_ids <- stats::na.omit(animal_ids)
    df$actual_id <- NA

    for (i in 1:length(positions)) {
      df[df$position == positions[[i]],][["actual_id"]] <- new_animal_ids[[i]]
    }

    df <- df %>%
      mutate(animal_id = as.factor(actual_id)) %>%
      select(-actual_id) %>%
      filter(!is.na(animal_id))

  } else if (exp_setup == "tube") {
    new_animal_ids <- stats::na.omit(animal_ids)
    n_animals <- new_animal_ids |>
      length()
    d <- density(stats::na.omit(df$x))
    highest_peaks <- data.frame(d[c("x", "y")])[c(F, diff(diff(d$y)>=0)<0),] |>
      arrange(y) |>
      slice_tail(n = n_animals) |>
      arrange(x) |>
      mutate(animal_id = new_animal_ids)

    # Found this solution at https://stackoverflow.com/a/43472391/13240268
    space <- stats::median(diff(highest_peaks$x)/2)
    cuts <- c(min(highest_peaks$x)-space, highest_peaks$x[-1]-diff(highest_peaks$x)/2, max(highest_peaks$x)+space)
    positions <- cut(df$x, breaks=cuts, labels=highest_peaks$animal_id) |>
      as_tibble() |>
      rename(animal_id = value)
    df <- df |>
      bind_cols(positions) |>
      stats::na.omit() |>
      group_by(animal_id, time) |>
      complete()

  } else {
    stop("No experimental setup given")
  }
  return(df)
}
