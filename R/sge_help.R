#' Return running jobs
#' @export
qst <- function(){
  system("qstat -u $USER", intern=TRUE)
}


#' Run and \code{cat} a call to \code{system}
#' @param cmd string of the command to run
#' @export
mysys <- function(cmd){
  cat(cmd,fill=T)
  system(cmd)
}


#' Submit jobs to SGE
#' @param dir directory of submission script
#' @export
submit <- function(dir=getwd()){
  wd <- getwd()
  setwd(dir)
  cmd <- paste0("qsub submit")
  mysys(cmd)
  setwd(wd)
}

#' Removes all files and folders created by \code{setup} and their contents
#' @param dir project directory name
#' @details Removes \code{results/*}, \code{SGE_Output/*}, \code{arg_grid.Rdata},
#' \code{submit}, \code{seeds.Rdata}, and \code{doone.R}.
#' @export
clean <- function(dir=getwd()){
  dir <- paste0(dir, "/")
  rdir <- paste0(dir, "results/")
  sdir <- paste0(dir, "SGE_Output/")
  arg_name <- paste0(dir, "arg_grid.Rdata")

  if(file.exists(rdir)){
    cmd <- paste0("rm -rf ", rdir, "")
    mysys(cmd)
    cmd <- paste0("rm -rf ", sdir, "")
    mysys(cmd)
    cmd <- paste0(paste0("rm ", arg_name))
    mysys(cmd)
    cmd <- paste0("rm ", dir, "submit")
    mysys(cmd)
    cmd <- paste0("rm ", dir, "doone.R")
    mysys(cmd)
    fn <- paste0(dir, "seeds.Rdata")
    if(file.exists(fn)){
      cmd <- paste0("rm ", dir, "seeds.Rdata")
      mysys(cmd)
    }
  }
}

#' sge_test
#' Simple test SGE configuration
#' @param dir directory in which to run test
#' @return A \code{gresults} object with the submitted plan
#' @export
sge_test <- function(dir=getwd()){
  f <- function(x,y){
    Sys.sleep(.2)
    stopifnot(x < 5)
    x
  }
  out <- gapply(f, x=3:8, y=1:2, .eval=F)
  plan <- setup(out, .dir=dir)
  submit(dir)
  return(plan)
}


