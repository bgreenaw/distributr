## Interactive setting up of simulation from gapply test object

#' setup sge simulation
#' @param object gapply object
#' @param dir directory name relative to the current working directory, ends in '/'
#' @param .reps total number of replications for each condition
#' @param .chunks split \code{.reps} across this many nodes (see details)
#' @param .mc.cores number of cores used to run replications in parallel
#' @param .verbose verbose level
#' @param .script.name name of script
#' @details 
#' The replications performed per chunk is computed as \code{ceiling(.reps/.chunks)}, which
#' will produce more total replications than requested if \code{.reps} is not evenly divisible by \code{.chunks}
#' @export
setup <- function(object, dir=getwd(),  .reps=1, .chunks = 1, .mc.cores=1, .verbose=1, .script.name="doone.R"){
  param.grid <- attr(object,"param.grid")
  dir <- paste0(dir, "/")
  ## Chunk is the slowest varying factor. So adding replications
  ## will be extending the grid within chunk by more chunks, which can then be 
  ## mapped onto SGE_TASK_ID. Don't change this unless you found something better design wise.
  chunk.grid <- param.grid[rep(1:nrow(param.grid), times=.chunks),,drop=F]
  chunk.grid$chunk <- rep(1:.chunks, each=nrow(param.grid))
  f <- attr(object,"f")
  reps.per.chunk <- ceiling(.reps/.chunks)
  
  cmd <- paste0("mkdir -p ", dir, "results") 
  mysys(cmd)
  cmd <- paste0("mkdir -p ", dir, "SGE_Output")
  mysys(cmd)
  
  write.submit(dir, script.name=.script.name, mc.cores=.mc.cores, tasks=nrow(chunk.grid))

  param.grid <- chunk.grid
  attr(param.grid, "reps") <- reps.per.chunk*.chunks # total actual reps
  attr(param.grid, "rpc") <- reps.per.chunk # reps per chunk
  save(param.grid, file=paste0(dir, "param_grid.Rdata"))
  
  write.do.one(f=f, dir=dir, reps=reps.per.chunk, mc.cores=.mc.cores, verbose=.verbose, script.name=.script.name)
}


#' @export
qst <- function(){
  mysys("qst")
}

#' @export
mysys <- function(cmd){
  cat(cmd,fill=T)
  system(cmd)
}

write.submit <- function(dir, script.name="doone.R", mc.cores=1, tasks=1){
  cmd <- paste0("touch ", dir, "submit")
  mysys(cmd)
  temp <- paste0("#!/bin/bash
#$ -M patr1ckm.crc@gmail.com     # Email address for job notification
#$ -m a          # Send mail when job begins, ends and aborts
#$ -pe smp ",mc.cores,"     # environment and legal core size
#$ -q *@@daccss  # Specify queue
#$ -N patr1ckm   # Specify job name
#$ -t 1:", tasks, "        # number of rows in param.grid
#$ -o SGE_Output

Rscript ", script.name, " $SGE_TASK_ID")
  cat(temp,file=paste0(dir, "submit"))
}

write.do.one <- function(f, dir, reps=1, mc.cores=1, verbose=1, script.name="doone.R"){
  fstr <- paste0("f <- ", paste0(deparse(eval(f), control="all"),collapse="\n"))
  temp <- paste0(fstr,"
  library(patr1ckm)
  args <- as.numeric(commandArgs(trailingOnly=TRUE))
  cond <- args[1]
  reps <- ", reps," # this is reps per chunk
  load('param_grid.Rdata')
  params <- param.grid[cond,]
  rep.id <- (reps*(params$chunk-1)+1):(reps*params$chunk)
  params$chunk <- NULL # because f doesn't take chunk usually
  res.l <- do.rep(f, as.list(params), .reps=reps, .rep.cores=", mc.cores, ", .verbose=", verbose," )
  dir <- paste0('results/')
  fn <- paste0(dir, cond,'.Rdata')
  save(res.l, file=fn)")
  
  cat(temp, file=paste0(dir, script.name))
}

#' Submit jobs to SGE
#' @export
submit <- function(dir=getwd()){
  wd <- getwd()
  setwd(dir)
  cmd <- paste0("qsub submit")
  mysys(cmd)
  setwd(wd)
}

#' Collect completed results files
#' 
#' @export
#' @importFrom gtools mixedsort
#' @importFrom tidyr gather
collect <- function(dir=getwd()){
  dir <- paste0(dir, "/")
  load(paste0(dir, "param_grid.Rdata"))
  
  rdir <- paste0(dir, "results/")
  conds.files <- gtools::mixedsort(paste0(rdir,list.files(rdir)))
  cond.l <- list()           # list of the results from each condition 
  for(i in 1:length(conds.files)){
      fn <- paste0(conds.files[i])
      load(fn)
      cond.l[[i]] <- res.l
  }
  
  cond.l <- unlist(cond.l, recursive=F) 
  
  cond.idx <- as.numeric(gsub(".Rdata", "", basename(conds.files))) # completed conditions
  cond.grid <- param.grid[cond.idx,]
  
  reps <- attr(param.grid, "reps") # Since this is from do.rep, will always be of length reps
  rpc <- attr(param.grid, "rpc")

  rep.id <- function(chunk, reps){ return((reps*(chunk-1)+1):(reps*chunk)) }
  
  reps <- unlist(lapply(cond.grid$chunk, rep.id, reps=rpc))
  rep.grid <- cond.grid[rep(1:nrow(cond.grid), each=rpc),]
  rep.grid$chunk <- NULL # the actual chunk doesn't matter since it just groups replications
  rep.grid$rep  <- reps
  
  err.id <- unlist(lapply(cond.l, is.error))
  err.param <- rep.grid[which(err.id),]
  err.list <- cond.l[err.id]
  names(err.list) <- which(err.id)
  
  value <- as.data.frame(do.call(rbind, cond.l[!err.id])) # automatic naming of unnamed returns to V1,V2, etc
  
  wide <- cbind(rep.grid[!err.id, ], value)
  
  long <- tidyr::gather(wide,key,value,-(1:(ncol(param.grid))))
  
  perc.complete <- length(cond.idx)/nrow(param.grid)
  perc.err <- mean(err.id)
  
  class(long) <- c("gapply", class(long))
  #attr(long, "time") <- NULL
  attr(long, "arg.names") <- head(colnames(param.grid),-1)
  #attr(long, "f") <- NULL
  #attr(long, "grid") <- param.grid
  attr(long, "err") <- data.frame(msg=unlist(err.list))
  attr(long, "reps") <- attr(param.grid, "reps")
  attr(long, "rpc") <- rpc
  attr(long, "perc.complete") <- perc.complete
  attr(long, "perc.err") <- perc.err
  
  return(long)
}

#' Cleans results
#' @param dir project directory name followed by 'slash'
#' @export
clean <- function(dir=getwd()){
  dir <- paste0(dir, "/")
  rdir <- paste0(dir, "results/")
  sdir <- paste0(dir, "SGE_Output/")
  if(file.exists(rdir)){
    cmd <- paste0("rm -rf ", rdir, "*")
    mysys(cmd)
    cmd <- paste0("rm -rf ", sdir, "*")
    mysys(cmd)
  }
}

#' sge
#' 
#' @export
sge <- function(dir=getwd()){
  f <- function(x,y){
    Sys.sleep(.5)
    stopifnot(x < 5)
    x
  }
  out <- gapply(f, x=3:8, y=1:2, .eval=F)
  setup(out, dir)
  submit(dir)
}

#' Return parameter grid
#' 
#' @export
param.grid <- function(dir=getwd()){
  load(paste0(dir, "/param_grid.Rdata"))
  return(param.grid)
}

