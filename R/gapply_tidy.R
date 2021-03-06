
#' Tidy results from grid_apply or dgraph
#'
#' Merges the results of \code{grid_apply} with the argument grid, with multiple return values
#' as separate columns.
#'
#' @param x results from \code{grid_apply} or \code{collect}
#' @param ... additional arguments passed to either \code{tidy.gresults} or
#' \code{tidy.dgraph}
#' @details
#' If results are of varying length, it can be useful to 'stack'
#' them into \code{key, value} pairs by setting \code{stack=TRUE}.
#' When stacking, vectors ar mapped to a single key and data frames are mapped to two keys (rownames and column names).
#' If the results are unnamed, names are assigned as in \code{as.data.frame}.
#' See \code{\link{stack_list}} for
#' further details.
#' @return Returns results as a \code{data.frame} in long form with
#'  the following columns:
#' \item{...}{Columns corresponding to grid of parameters given in
#' \code{expand.grid(...)}}
#' \item{\code{rep}}{the replication number}
#' \item{\code{value}}{the value of \code{f} at a set of parameters}
#' @seealso \code{\link{stack_list}}
#' @export
tidy <- function(x, ...){
  UseMethod("tidy")
}


#' @param arg_grid argument grid; if NULL (default) looks for arg_grid
#'  as an attribute to \code{x}
#' @param stack if \code{TRUE} (default) stack results into \code{key, value} pairs. Otherwise, \code{bind_rows} is used. (requires \code{dplyr})
#' @param .reps scalar or vector of completed replications for each job (usually given via \code{collect})
#' @export
#' @describeIn tidy Tidy an object from \code{grid_apply} or \code{collect}
tidy.gapply <- function(x, arg_grid=NULL, stack=FALSE, .reps=NULL, ...){
  if(is.null(arg_grid)){
    arg_grid <- attr(x, "arg_grid")
    if(is.null(arg_grid)) stop("can't tidy, no argument grid")
  }
  if(is.null(.reps)) .reps <- attr(x, ".reps")
  if(length(.reps) == 1){
    # from grid_apply
    rep_grid <- arg_grid[rep(1:nrow(arg_grid), each=.reps), , drop=F]
    #if(nrow(rep_grid) != length(x)) stop("number of replications isn't correct, try setting .reps=NULL")
    rep_grid$.rep  <- rep(1:.reps, times=nrow(arg_grid))
  } else {
    # completed replications, from collect
    #if(length(x) != length(.reps)) stop("length(reps) should be 1 or length(x)")
    rep_grid <- arg_grid[rep(1:nrow(arg_grid), times=.reps), , drop=F]
    rep_grid$.rep <- unlist(lapply(.reps, seq_len))
  }

  # Stack results, adding keys according to names of elements, colnames, and rownames.
  if(stack){
    if (!requireNamespace("dplyr", quietly = TRUE)) {
      stop("dplyr needed to stack Please install it.",
           call. = FALSE)
    }
    value <- stack_list(x)
    # Expand rows by number of keys
    if(is.data.frame(x[[1]])){
      nkeys <- sapply(x, function(xi){prod(dim(xi))})
    } else if(is.list(x[[1]])){
      nkeys <- sapply(x, function(xi){sum(lengths(xi))})
    } else {
      nkeys <- sapply(x, length)
    }
    value_grid <- rep_grid[rep(1:nrow(rep_grid), times = nkeys), ]

  } else {
    #values <- bind_rows(x) # this seg faults when l[[i]] is scalar
    if(any(lengths(x) != length(x[[1]]))) stop("cannot tidy, try tidy(., stack=T)")
    value <- do.call(rbind, x)
    if(is.data.frame(x[[1]])){
      nkeys <- sapply(x, function(xi){nrow(xi)})
      value_grid <- rep_grid[rep(1:nrow(rep_grid), times = nkeys), ]
    } else {
      value <- do.call(rbind, x)
      value_grid <- rep_grid
    }
  }

  rownames(value_grid) <- NULL
  res <- cbind(value_grid, value)

  new.attr.names <- setdiff(names(attributes(x)), names(attributes(res)))
  attributes(res)[new.attr.names] <- attributes(x)[new.attr.names]
  attr(res, "class") <- c("gresults", class(res))
  return(res)
}



#' Stacks a list of vectors, lists, or data frames
#'
#' Stacks a list of vectors, lists, or data frames into a tibble with \code{key} and \code{value} columns,
#' us
#'
#' @param  xl list of vectors, lists, or data frames
#' @return tibble with \code{key}, and \code{value} as columns; \code{key2} if list of data frames. \code{key} and \code{key2} are not factors.
#' @export
#' @details
#'  Stacks a vector or list into \code{key} and \code{value} columns, where \code{key} takes the names of the elements,
#'  if the names are null, assigns names.
#'
#' Stacks a list of vectors into \code{key} and \code{value} columns, where \code{key} takes the names of the elements,
#'  if the names are null, assigns names.
#'
#' Stacks a data frame or list of vectors of the same length into \code{key}, \code{key2}, and \code{value} columns,
#'  where \code{key} and \code{key2} are the column and row names of the first element of \code{xl}. If names are null, assigns names.
#'
stack_list <- function(xl){
  x <- xl[[1]]
  if(is.data.frame(x)){
    dims <- lapply(xl, dim)
    same_dimensions <- all(sapply(dims, function(dims){ identical(dims, dim(x))}))

    if(same_dimensions){
      value <- dplyr::data_frame(key = rep(rep(colnames(x), each = nrow(x)), times = length(xl)),
                          key2 = rep(rownames(x), times = length(xl) * ncol(x)),
                          value = unlist(xl, use.names = F))
    } else {
      value <- dplyr::bind_rows(lapply(xl, stack_x))
    }

  } else if(is.list(x)){
    lens <- lapply(xl, lengths)
    same_dimensions <- all(sapply(lens, function(dims){ dims == lengths(x) }))

    if(same_dimensions){
      x <- as.data.frame(x)
      value <- dplyr::data_frame(key = rep(rep(colnames(x), each = nrow(x)), times = length(xl)),
                          key2 = rep(rownames(x), times = length(xl) * ncol(x)),
                          value = unlist(xl, use.names = F))
    } else {
      # future: consider unlist(xl) with key=names(unlist(xl))?
      value <- dplyr::bind_rows(lapply(xl, stack_x))
    }

  } else {
    same_dimensions <- all(sapply(xl, length) == length(x))

    if(same_dimensions){
      if(is.null(names(x))){
        value <- dplyr::data_frame(key = rep(paste0("V", seq_along(x)), times = length(xl)),
                            value = unlist(xl, use.names = F))
      } else {
        value <- dplyr::data_frame(key = rep(names(x), times = length(xl)),
                            value = unlist(xl, use.names = F))
      }
    } else{
      value <- dplyr::bind_rows(lapply(xl, stack_x))
    }
  }
  return(value)
}


#' Stack a simple vector or data frame into key and value columns
#'
#' Stacks a vector or list into \code{key} and \code{value} columns, where key takes the names of the elements, or
#' assigns names if null.
#'
#' Stacks a list of vectors into \code{key} and \code{value} columns, where key names its elements automatically
#'
#' Stacks a data frame into \code{key} (key2) and \code{value} columns, where key and key2 are the column
#' and row names of x.
#'
#' @param x a vector or data frame
stack_x <- function(x){
  if(is.data.frame(x)){
      dplyr::data_frame(key = rep(colnames(x), each = nrow(x)),
                 key2 = rep(rownames(x), times = ncol(x)),
                 value = unlist(x, use.names = F))
  } else {
    if(is.list(x)) x <- unlist(x)

    if(is.null(names(x))){
      dplyr::data_frame(key = paste0("V", seq_along(x)), value = x)
    } else {
      dplyr::data_frame(key = names(x), value = x)
    }
  }
}

