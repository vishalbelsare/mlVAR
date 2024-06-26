aveMean <- function(x){
  mean(x,na.rm=TRUE)
}

aveCenter <- function(x, scale = FALSE){
  x <- x - mean(x,na.rm=TRUE)
  if (scale){
    x <- x / sd(x,na.rm=TRUE)
  }
  x
}

aveScaleNoCenter <- function(x){
  meanGroup <- mean(x,na.rm=TRUE)
  x <- x - meanGroup
  x <- x / sd(x,na.rm=TRUE)
  x + meanGroup
}

aveLag <- function(x, lag=1){
  # Then lag:
  if (lag > length(x)){
    return(rep(NA,length(x)))
  } else {
    return(c(rep(NA,lag),head(x,length(x)-lag))) 
  }
}

Scale <- function(x){
  SD <- sd(x,na.rm=TRUE)
  if (length(SD) == 0 || is.na(SD)){
    SD <- 0
  }
  if (SD == 0){
    x[] <- 0
    return(x)
  } else {
    return((x - mean(x,na.rm=TRUE)) / SD)
  }
}


mlVAR <- function(
  data, # Data frame
  
  # Variable names:
  vars, # Vector of variables to include in analysis
  idvar, # String indicating the subject id variable name 
  lags = 1, # Vector indicating the lags to include. Defaults to 1
  dayvar, # string indicating the measurement id variable name (if missing, every measurement is set to one day). Used to not model scores over night
  beepvar, # String indicating beep per day (is missing, is added)
  # timevar, # Only used for maxtimeDifference
  
  # Estimation options:
  # orthogonal, # TRUE or FALSE for orthogonal edges. Defaults to nvar < 6
  estimator = c("default","lmer","lm","Mplus"), # Add more? estimator = "least-squares" IGNORES multi-level
  contemporaneous = c("default","correlated","orthogonal","fixed","unique"), # IF NOT FIXED: 2-step estimation method (lmer again on residuals)
  temporal = c("default", "correlated","orthogonal","fixed","unique"), # Unique = multi-level!
  # betweenSubjects = c("default","GGM","posthoc"), # Should covariances between means be estimated posthoc or as a GGM? Only used when method = "univariate"
  nCores = 1, # Number of computer cores
  # Misc:
  # maxTimeDiff, # If not missing. maximum time difference.
  # LMERcontrol = list(optimizer = "bobyqa"), # "bobyqa"  or "Nelder_Mead"
  # JAGSoptions = list(),
  verbose = TRUE, # Include progress bar?
  compareToLags,
  scale = TRUE, # standardize variables grand mean before estimation
  scaleWithin = FALSE, # Scale variables within-person
  AR = FALSE, # Set to TRUE to estimate AR models instead
  MplusSave = TRUE,
  MplusName = "mlVAR",
  iterations = "(2000)",
  chains = nCores,
  signs,
  
  orthogonal, # Used for backward competability
  
  trueMeans # Optional data frame with true personwise means to plug in
  
  # nCores = 1,
  # JAGSexport = FALSE, # Exports jags files
  # n.chain = 3,
  # n.iter = 10000,
  # estOmega = FALSE
  # ...
)
{
  if (0 %in% lags & length(lags) > 1){
    stop("0 in 'lags' ignored; contemporaneous relationships are estimated by default.")
    lags <- lags[lags!=0]
  }
  # First check the estimation options:
  # method <- match.arg(method)
  estimator <- match.arg(estimator)
  # contemporaneous <- match.arg(contemporaneous)
  # betweenSubjects <- match.arg(betweenSubjects)
  # temporal <- match.arg(temporal)
  betweenSubjects <- "GGM"
  
  # Nuclear option on JAGS:
  if (estimator == "JAGS"){
    stop("'JAGS' estimator is not implemented yet and expected in a later version of mlVAR.")
  }
  
  #   # Only estimate omega when estimator is JAGS
  #   if (estOmega & estimator != "JAGS"){
  #     stop("Cannot estimate Omega when estimator is not JAGS.")
  #   }
  
  # Some dummies for later versions:
  # temporal <- "unique"
  temporal <- match.arg(temporal)
  contemporaneous <- match.arg(contemporaneous)
  
  if (!missing(orthogonal)){
    temporal <- ifelse(orthogonal,"orthogonal","correlated")
    warning(paste0("'orthogonal' argument is deprecated Setting temporal = '",temporal,"'"))
  }
  #   
  
  #   if (betweenSubjects != "default"){
  #     if (estimator != "lmer"){
  #       warning("'betweenSubjects' argument not used in estimator.")
  #     }
  #   } else {
  #     betweenSubjects <- ifelse(estimator == "least-squares","posthoc","GGM")
  #   }
  
  
  # Unimplemented methods:
  #   if (method == "multivariate" & estimator == "lmer"){
  #     stop("Multivariate estimation using 'lmer' is not implemented.")
  #   }
  #   if (contemporaneous == "unique" & estimator %in% c("lmer")){
  #     stop(paste0("Unique contemporaenous effects estimation not implemented for estimator = '",estimator,"'"))
  #   }
  
  # Obtain variables from mlVARsim0:
  if (is(data,"mlVARsim0")){
    vars <- data$vars
    idvar <- data$idvar
    data <- data$Data
  }
  
  if (is(data,"mlVARsim")){
    vars <- data$vars
    idvar <- data$idvar
    lags <- data$lag
    data <- data$Data
  }
  
  if (missing(lags)){
    lags <- 1
  }
  
  # Set temporal to fixed if lag-0:
  if (all(lags==0)){
    temporal <- "fixed"
  }
  
  # Set orthogonal:
  if (estimator == "default"){
    if (temporal == "unique"){
      estimator <- "lm"
    } else {
      estimator <- "lmer"
    }
    if (verbose) {
      message(paste0("'estimator' argument set to '",estimator,"'"))
    }
  }
  
  if (nCores != 1 && !estimator %in% c("Mplus","lmer")){
    stop("'nCores > 1' only supported for 'lmer' and 'Mplus' estimator.")
  }
  
  if (temporal == "default"){
    if (length(vars) > 6){
      
      temporal <- "orthogonal"
      
    } else {
      temporal <- "correlated"
    }  
    if (verbose) {
      message(paste0("'temporal' argument set to '",temporal,"'"))
    }
  }
  
  if (contemporaneous == "default"){
    if (length(vars) > 6){
      
      contemporaneous <- "orthogonal"
      
    } else {
      contemporaneous <- "correlated"
    }  
    
    if (verbose) {
      message(paste0("'contemporaneous' argument set to '",contemporaneous,"'"))
    }
  }
  
  ### Check input ###
  if (estimator == "lmer"){
    if (temporal %in% c("unique")){
      stop("'lmer' estimator does not support temporal = 'unique'")
    }
  }
  if (estimator == "Mplus"){
    if (temporal %in% c("unique")){
      stop("'Mplus' estimator does not support temporal = 'unique'")
    }
    
    if (contemporaneous %in% c("unique")){
      stop("'Mplus' estimator does not support contemporaneous = 'unique'")
    }
  }
  
  
  
  if (estimator == "lm"){
    if (!temporal %in% c("unique")){
      stop("'lm' estimator only supports temporal = 'unique'")
    }
  }
  
  # CompareToLags:
  if (missing(compareToLags)){
    compareToLags <- lags
  }
  if (length(compareToLags) < length(lags)){
    stop("'compareToLags' must be at least as long as 'lags'")
  }
  
  # Check input:
  stopifnot(!missing(vars))
  stopifnot(!missing(idvar))
  if (!is.character(vars) ||  !all(vars %in% names(data))){
    stop("'vars' must be a string vector indicating column names of the data.")
  }
  
  # input list (to include in output):
  # input <- list(vars = vars, lags = lags, estimator=estimator,temporal = temporal)
  
  # Add day id if missing:
  if (missing(idvar))
  {
    idvar <- "ID"
    data[[idvar]] <- 1
  } else {
    if (!is.character(idvar) || length(idvar) != 1 || !idvar %in% names(data)){
      stop("'idvar' must be a string indicating a column name of the data.")
    }
  } # else input$idvar <- idvar
  
  # Add day var if missing:
  if (missing(dayvar))
  {
    dayvar <- "DAY"
    data[[dayvar]] <- 1
  } else {
    if (estimator == "Mplus"){
      warning("estimator = 'Mplus' does not support dayvar argument. Day variable is ignored in computation. Days can manually be added by using 'beepvar' in combination with missing beeps (e.g., for 5 measurements per day, add a column with values 1, 2, 3, 4, 5, 9, 10, etcetera and refer the column in the 'beepvar' argument).")
      
    }
    if (!is.character(dayvar) || length(dayvar) != 1 || !dayvar %in% names(data)){
      stop("'dayvar' must be a string indicating a column name of the data.")
    }
  }# else input$dayvar <- dayvar
  
  # Add beep var if missing:
  if (missing(beepvar))
  {
    beepvar <- "BEEP"
    data[[beepvar]] <- ave(seq_len(nrow(data)),data[[idvar]],data[[dayvar]],FUN = seq_along)
  } else {
    if (!is.character(beepvar) || length(beepvar) != 1 || !beepvar %in% names(data)){
      stop("'beepvar' must be a string indicating a column name of the data.")
    }
    
    if (any(duplicated(data[[beepvar]])) && estimator == "Mplus"){
      warning("Duplicated beeps found with estimator = 'Mplus'. Input is likely not proper.")
    }
  }# else input$beepvar <- beepvar
  
  ### INPUT CHECK ###
  if (!is.numeric(data[[beepvar]])){
    stop("Beep variable is not numeric")
  }
  
  
  # Remove NA day or beeps:
  data <- data[!is.na(data[[idvar]]) & !is.na(data[[dayvar]]) & !is.na(data[[beepvar]]), ]
  
  ### STANDARDIZE DATA ###
  # Test for rank-deficient:
  X <- as.matrix(na.omit(data[,vars]))
  qrX <- qr(X)
  rnk <- qrX$rank
  
  if (rnk < length(vars)){
    # Which node is not being nice?
    keep <- qrX$pivot[1:rnk]
    discard <- vars[!seq_along(vars)%in%keep]
    
    warning(paste0("The following variables are linearly dependent on other columns, and therefore dropped from the mlVAR analysis:\n",
                   paste("\t-",discard,collapse="\n")))
    
    # If only one, we can find it out:
    if (rnk == length(vars) - 1){
      drop <- qrX$pivot[length(qrX$pivot)]
      test <- try(qr.solve(X[,-drop],X[,drop]))
      if (!is(test,"try-error")){
        test <- round(test,4)
        test <- test[test!=0]
        msg <- paste0(discard," = ",paste(test," * ",names(test),collapse=" + "))
        warning(msg)
      }
    }
    
    vars <- vars[keep]
    
  }
  
  # If trueMeans is supplied, within-person center and re-add true means:
  if (!missing(trueMeans)){
    for (v in vars){
        data[[v]] <-  ave(data[[v]],data[[idvar]], FUN = function(xx)aveCenter(xx)) + trueMeans[[v]][match(data[[idvar]], trueMeans[[idvar]])]
    }
  }

    
  # Standardize across all variables:
  if (scale){
    for (v in vars){
      data[[v]] <- Scale(data[[v]])
    }
  }
  
  
  ### Codes from murmur
  # Create murmur-like predictor data-frame:
  # Within-subjects model:
  PredModel <- expand.grid(
    dep = vars,
    pred = vars,
    lag = compareToLags[compareToLags!=0],
    type =  "within",
    stringsAsFactors = FALSE
  )
  
  
  # Between-subjects model:
  if (betweenSubjects == "GGM" & estimator == "lmer"){
    between <- expand.grid(dep=vars,pred=vars,lag=NA,type="between",
                           stringsAsFactors = FALSE)
    
    between <- between[between$dep != between$pred,]
    
    PredModel <- rbind(PredModel,between )
  }
  
  # Unique predictors:
  UniquePredModel <- PredModel[!duplicated(PredModel[,c("pred","lag","type")]),c("pred","lag","type")]
  
  # Add ID:
  if (estimator != "Mplus"){
    UniquePredModel$predID <- paste0("Predictor__",seq_len(nrow(UniquePredModel)))
  }
  # } else {
  #   UniquePredModel$predID <- paste0("b_",seq_len(nrow(UniquePredModel)))
  # }
  
  # Left join to total:
  PredModel <- PredModel %>% left_join(UniquePredModel, by = c("pred","lag","type"))
  
  # Augment the data
  augData <- data
  
  # Add missing rows for missing beeps

  
  # Check for errors in data:
  beepsummary <- data %>% group_by(.data[[idvar]],.data[[dayvar]],.data[[beepvar]]) %>% tally
  if (any(beepsummary$n!=1)){
    print_and_capture <- function(x)
    {
      paste(capture.output(print(x)), collapse = "\n")
    }
    
    warning(paste0("Some beeps are recorded more than once! Results are likely unreliable.\n\n",print_and_capture(
      beepsummary %>% filter(.data[["n"]]!=1) %>% select(.data[[idvar]],.data[[dayvar]],.data[[beepvar]]) %>% as.data.frame
    )))
  }
  
   beepsPerDay <-  dplyr::summarize(data %>% group_by(.data[[idvar]],.data[[dayvar]]), 
                                                    first = min(.data[[beepvar]],na.rm=TRUE),
                                                    last = max(.data[[beepvar]],na.rm=TRUE))

  
  # all beeps:
  allBeeps <- expand.grid(unique(data[[idvar]]),unique(data[[dayvar]]),seq(min(data[[beepvar]],na.rm=TRUE),max(data[[beepvar]],na.rm=TRUE)),stringsAsFactors = FALSE) 
  names(allBeeps) <- c(idvar,dayvar,beepvar)
  
  # Left join the beeps per day:
   allBeeps <- allBeeps %>% dplyr::left_join(beepsPerDay, by = c(idvar,dayvar)) %>% 
      dplyr::group_by(.data[[idvar]],.data[[dayvar]]) %>% dplyr::filter(.data[[beepvar]] >= .data$first, .data[[beepvar]] <= .data$last)%>%
      dplyr::arrange(.data[[idvar]],.data[[dayvar]],.data[[beepvar]])
  
  
   ### Check true means structure:
   if (!missing(trueMeans)){
     # Check if ID variables is in the trueMeans object:
     if (!idvar %in% names(trueMeans)){
       stop("ID variable not found in 'trueMeans' object.")
     }
     
     # check if all variables are in trueMeans object:
     if (!all(vars %in% names(trueMeans))){
       stop("Not all variables in 'vars' are found in 'trueMeans' object.")
     }
     
     # Check if all IDs are in trueMeans object:
     if (!all(unique(data[[idvar]]) %in% unique(trueMeans[[idvar]]))){
       stop("Not all IDs in data are found in 'trueMeans' object.")
     }
   }
   
    # FIXME: Need to center dependent variable and add true means!
   
  
  ## Enter NA's:
  #augData <- augData %>% right_join(allBeeps, by = c(idvar,dayvar,beepvar)) %>%
  
   # Enter NA's:
  augData <- augData %>% dplyr::right_join(allBeeps, by = c(idvar,dayvar,beepvar)) %>%
    arrange(.data[[idvar]],.data[[dayvar]],.data[[beepvar]])
  

  # Add the predictors (when estimatior != JAGS or Mplus):
  if (!estimator %in% c("Mplus","JAGS")){
    for (i in seq_len(nrow(UniquePredModel))){
      # between: add mean variable:
      
      if (UniquePredModel$type[i] == "between"){
        if (estimator == "lmer"){
          if (missing(trueMeans)){
            augData[[UniquePredModel$predID[i]]] <- ave(augData[[UniquePredModel$pred[i]]],augData[[idvar]], FUN = aveMean)            
          } else {
            augData[[UniquePredModel$predID[i]]] <- trueMeans[[UniquePredModel$pred[i]]][match(augData[[idvar]],trueMeans[[idvar]])]
          }
          
        }
      } else {
        # First include:
        augData[[UniquePredModel$predID[i]]] <-  ave(augData[[UniquePredModel$pred[i]]],augData[[idvar]],augData[[dayvar]], FUN = function(x)aveLag(x,UniquePredModel$lag[i]))
        
        # Then center:
        ### CENTERING ONLY NEEDED WHEN ESTIMATOR != JAGS ###
        if (!estimator %in% c("JAGS")){
          if (missing(trueMeans)){
            augData[[UniquePredModel$predID[i]]] <- ave(augData[[UniquePredModel$predID[i]]],augData[[idvar]], FUN = function(xx)aveCenter(xx,scale=scaleWithin))
          } else {
            augData[[UniquePredModel$predID[i]]] <- augData[[UniquePredModel$predID[i]]] - trueMeans[[UniquePredModel$pred[i]]][match(augData[[idvar]],trueMeans[[idvar]])]
            if (scaleWithin){
              augData[[UniquePredModel$predID[i]]] <- ave(augData[[UniquePredModel$predID[i]]],augData[[idvar]], aveScaleNoCenter)
            } 
              
              
          }
          
        } 
      }
      
    }
  }
  
  # Also within-person standardize dependent vars if scaleWithin = TRUE
  if (isTRUE(scaleWithin)){
    for (i in seq_along(vars)){
      augData[[vars[i]]] <- ave(augData[[vars[i]]],augData[[idvar]], FUN = function(xx)aveScaleNoCenter(xx))
    }
  }
  
  # Remove missings from augData:
  if (!estimator %in% c("JAGS","Mplus")){
    Vars <- unique(c(PredModel$dep,PredModel$predID,idvar,beepvar,dayvar))
    augData <- na.omit(augData[,Vars])
    PredModel <- PredModel[is.na(PredModel$lag) | (PredModel$lag %in% lags),]
  } # JAGS and Mplus handle missings!
  
  # check AR:
  if (AR && estimator != "lmer"){
    stop("AR = TRUE only supported for estimator = 'lmer'")
  }
  
  # Check data:
  tab <- table(augData[[idvar]])
  if (any(tab < 20)){
    warning(sum(tab<20)," subjects detected with < 20 measurements. This is not recommended, as within-person centering with too few observations per subject will lead to biased estimates (most notably: negative self-loops).")
  }
  
  #### RUN THE MODEL ###
  if (estimator == "lmer"){
    
    Res <- lmer_mlVAR(PredModel,augData,idvar,verbose=verbose, contemporaneous=contemporaneous,temporal=temporal,
                      nCores=nCores, AR = AR)
    # } else if (estimator == "stan"){
    # Res <- stan_mlVAR(PredModel,augData,idvar,verbose=verbose,temporal=temporal,nCores=nCores,...)    
    
  } else if (estimator == "lm"){
    Res <- lm_mlVAR(PredModel,augData,idvar,temporal=temporal,contemporaneous=contemporaneous, verbose=verbose)
    #   } else if (estimator == "JAGS"){
    #     Res <- JAGS_mlVAR(augData, vars, 
    #                       idvar,
    #                       lags, 
    #                       dayvar, 
    #                       beepvar,
    #                       temporal = temporal,
    #                       orthogonal = orthogonal, verbose=verbose, contemporaneous=contemporaneous,
    #                       JAGSexport=JAGSexport,
    #                       n.chain = n.chain, n.iter=n.iter,estOmega=estOmega)
  } else if (estimator == "Mplus"){
    Res <- Mplus_mlVAR(PredModel,augData,idvar,temporal=temporal,contemporaneous=contemporaneous, verbose=verbose,MplusSave=MplusSave, MplusName=MplusName,iterations=iterations,
                       chains=chains, nCores = nCores,signs=signs)
    
  } else  stop(paste0("Estimator '",estimator,"' not yet implemented."))
  
  
  # Add input:
  Res[['input']] <- list(
    vars = vars, 
    lags = lags,
    compareToLags=compareToLags,
    estimator = estimator,
    temporal = temporal,
    AR = AR
  )
  
  if (estimator == "lmer"){
    Res$IDs <- rownames(ranef(Res$output$temporal[[1]])[[idvar]])    
  } else {
    Res$IDs <- NULL
  }

  
  return(Res)
  
}

