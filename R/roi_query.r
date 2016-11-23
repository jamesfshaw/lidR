# ===============================================================================
#
# PROGRAMMERS:
#
# jean-romain.roussel.1@ulaval.ca  -  https://github.com/Jean-Romain/lidR
#
# COPYRIGHT:
#
# Copyright 2016 Jean-Romain Roussel
#
# This file is part of lidR R package.
#
# lidR is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>
#
# ===============================================================================


#' Extract LiDAR data from based on a set of coordinates
#'
#' When the user has a set of (x, y) coordinates corresponding to a region of interest (ROI)
#' (a ground inventory for example), he can automatically extract the lidar data associated
#' to the ROIs from a Catalog. The algorithm automatically extracts ROIs even falling on the edges
#' of one or more tiles.\cr
#' It works only for tiles well organized as a damier.
#'
#' @aliases roi_query
#' @param obj A Catalog object
#' @param x vector. A set of x coordinates corresponding to the center of the ROI
#' @param y vector. A set of y coordinates corresponding to the center of the ROI
#' @param r numeric or vector. A radius or a set of radii of the ROI. If only
#' r is provided (r2 = NULL) it will extract data falling into a disc.
#' @param r2 numeric or vector. A radius or a set of radii of plots. If r2
#' is provided, the selection turns into a rectangular ROI. If r = r2 it is a square obviouly.
#' @param roinames vector. A set of ROI names (the ID of the plots for example)
#' @param mc.cores numeric. The number of cores for parallel processing (see \link[parallel:makeCluster]{makeCluster})
#' @param ... additionnal parameters for \link[lidR:readLAS]{readLAS}
#' @return A list of LAS objects
#' @export roi_query
#' @importFrom dplyr progress_estimated
#' @importFrom utils lsf.str
#' @importFrom magrittr %>% %<>%
#' @importFrom parallel makeCluster stopCluster parLapply clusterExport
#' @examples
#' \dontrun{
#' # Build a Catalog
#' catalog = Catalog("<Path to a folder containing a set of las or laz files>")
#'
#' # Get coordinates from an external file
#' X = runif(30, 690000, 800000)
#' Y = runif(30, 5010000, 5020000)
#' R = 25
#'
#' # Return a List of 30 circular LAS objects of 25 m radius (50 m diameter)
#' catalog %>% roi_query(X, Y, R)
#'
#' # Return a List of 30 square LAS objects of 50x50 m
#' catalog %>% roi_query(X, Y, R, R)
#' }
setGeneric("roi_query", function(obj, x, y, r, r2 = NULL, roinames = NULL, mc.cores = NULL, ...){standardGeneric("roi_query")})

#' @rdname roi_query
setMethod("roi_query", "Catalog",
  function(obj, x, y, r, r2 = NULL, roinames = NULL, mc.cores = NULL, ...)
  {
    . <- tiles <- NULL

    nplot = length(x)
    shape = if(is.null(r2)) 0 else 1

    if(is.null(roinames)) roinames = paste0("ROI", 1:nplot)

    # Make an index of the file in which are each query
    lasindex = obj %>% roi_index(x, y, r, r2,roinames)

    # Group the index of idendical queries with the aim to reduce number ofqueries
    lasindex = lasindex[, .(roinames = list(roinames),
                            X = list(x), Y = list(y),
                            r = list(r), r2 = list(r2),
                            tiles = list(unique(unlist(tiles)))),
                        by = list(paste(tiles))][,paste := NULL]

    lasindex = apply(lasindex, 1, as.list)

    cat("Extracting data...\n")

    if(is.null(mc.cores) | mc.cores == 1)
    {
      p = dplyr::progress_estimated(nplot)
      output = lapply(lasindex, .getGrpQuery, shape, p, ...)
    }
    else
    {
      cl = parallel::makeCluster(mc.cores, outfile = "")
      parallel::clusterExport(cl, varlist=c(lsf.str(envir = globalenv()), ls(envir = environment())), envir = environment())
      output = parallel::parLapply(cl, lasindex, .getGrpQuery, shape, ...)
      parallel::stopCluster(cl)
    }

    output = unlist(output)
    output = output[match(roinames, names(output))]  # set back to the original order

    cat("\n")

    return(output)
  }
)

.getGrpQuery = function(query, shape, p = NULL, ...)
{
  X      = query$X
  Y      = query$Y
  r      = query$r
  r2     = query$r2
  files  = query$tiles

  lidar  = readLAS(files, ...)
  output = vector("list", length(X))

  for(j in 1:length(X))
  {
    if(shape == 0)
      output[[j]] = clipCircle(lidar, X[j], Y[j], r[j])
    else
      output[[j]] = clipRectangle(lidar, X[j]-r[j], Y[j]-r2[j], X[j]+r[j], Y[j]+r2[j])

    if(!is.null(p))
      p$tick()$print()
    else
      cat(sprintf("%s ", query$roinames[j]))
  }

  names(output) = query$roinames[[1]]
  rm(list = "lidar") ; gc()

  return(output)
}
