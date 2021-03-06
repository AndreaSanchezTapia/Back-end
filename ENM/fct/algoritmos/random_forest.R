do_randomForest <- function(sp,
                            coordinates,
                            partitions,
                            buffer = FALSE,
                            seed = 512,
                            predictors,
                            models.dir,
                            project.model,
                            projections,
                            mask,
                            n.back = 500) {
  library(randomForest)
  cat(paste("Random Forests", "\n"))

  if (file.exists(paste0(models.dir)) == FALSE)
    dir.create(paste0(models.dir))
  if (file.exists(paste0(models.dir, "/", sp)) == FALSE) 
    dir.create(paste0(models.dir, "/", sp))
  if (project.model == T) {
    for (proj in projections) {
      if (file.exists(paste0(models.dir, "/", sp, "/", proj)) == FALSE) 
        dir.create(paste0(models.dir, "/", sp, "/", proj))
    }
  }

  # tabela de valores
  presvals <- raster::extract(predictors, coordinates)

  if (buffer %in% c("mean", "max")) {
    source("../../fct/createBuffer.R")
    backgr <- createBuffer(coord = coordinates, n.back = n.back, buffer.type = buffer,
      occs = coordinates, sp = sp, seed = seed, predictors = predictors)
  } else {
    set.seed(seed + 2)
    backgr <- randomPoints(predictors, n.back)
  }

  colnames(backgr) <- c("lon", "lat")

  # Extraindo dados ambientais dos bckgr
  backvals <- raster::extract(predictors, backgr)
  pa <- c(rep(1, nrow(presvals)), rep(0, nrow(backvals)))

  # Data partition
  if (nrow(coordinates) < 11)
    partitions <- nrow(coordinates)
  set.seed(seed)  #reproducibility
  group <- kfold(coordinates, partitions)
  set.seed(seed + 1)
  bg.grp <- kfold(backgr, partitions)
  group.all <- c(group, bg.grp)

  pres <- cbind(coordinates, presvals)
  back <- cbind(backgr, backvals)
  rbind_1 <- rbind(pres, back)
  sdmdata <- data.frame(cbind(group.all, pa, rbind_1))
  rm(rbind_1)
  rm(pres)
  rm(back)
  gc()
  write.table(sdmdata, file = paste0(models.dir, "/", sp, "/sdmdata.txt"))


  ##### Hace los modelos
  for (i in unique(group)) {
    cat(paste(sp, "partition number", i, "\n"))
    pres_train <- coordinates[group != i, ]
    if (nrow(coordinates) == 1)
      pres_train <- coordinates[group == i, ]
    pres_test <- coordinates[group == i, ]

    backg_train <- backgr[bg.grp != i, ]  #not used?
    backg_test <- backgr[bg.grp == i, ]  #new

    sdmdata_train <- subset(sdmdata, group != i)  #new
    sdmdata_test <- subset(sdmdata, group == i)  #new

    envtrain <- subset(sdmdata_train, select = c(-group, -lon, -lat))  #new
    envtest <- subset(sdmdata_test, select = c(-group, -lon, -lat))
    envtest_pre <- subset(sdmdata_test, pa == 1, select = c(-group, -lon, -lat,
      -pa))  #new
    envtest_back <- subset(sdmdata_test, pa == 0, select = c(-group, -lon, -lat,
      -pa))  #new












    # rf1 <- tuneRF(x=envtrain,y=sdmdata_train$pa,stepFactor = 0.5)
    rf <- randomForest(sdmdata_train$pa ~ ., data = envtrain)
    # rf <- randomForest (x =envtrain ,y=factor(sdmdata_train$pa),xtest=envtest,ytest
    # = factor(sdmdata_teste$pa))#fazendo teste interno a funcao evaluate nao serve
    # :(
    
    erf <- evaluate(envtest_pre, envtest_back, rf)
    rf_TSS <- max(erf@TPR + erf@TNR) - 1
    
    thresholdrf <- erf@t[which.max(erf@TPR + erf@TNR)]
    thrf <- threshold(erf)
    thrf$AUC <- erf@auc
    thrf$TSS <- rf_TSS  #raro
    thrf$algoritmo <- "rf"
    thrf$partition <- i
    row.names(thrf) <- paste(sp, i, "rf")
    
    rf_cont <- predict(predictors, rf, progress = "text", type = "response")
    rf_bin <- rf_cont > thresholdrf
    rf_cut <- rf_bin * rf_cont
    # rf1_cut <- rf1_cut/maxValue(rf1_cut)

    write.table(thrf, file = paste0(models.dir, "/", sp, "/evaluate", 
      sp, "_", i, "_randomforest.txt"))

    if (class(mask) == "SpatialPolygonsDataFrame") {
      source("../../fct/cropModel.R")
      rf_cont <- cropModel(rf_cont, mask)
      rf_bin <- cropModel(rf_bin, mask)
      rf_cut <- cropModel(rf_cut, mask)
    }
    writeRaster(x = rf_cont, filename = paste0(models.dir, "/", sp, "/rf_cont_", 
      sp, "_", i, ".tif"), overwrite = T)
    writeRaster(x = rf_bin, filename = paste0(models.dir, "/", sp, "/rf_bin_", sp, 
      "_", i, ".tif"), overwrite = T)
    writeRaster(x = rf_cut, filename = paste0(models.dir, "/", sp, "/rf_cut_", sp, 
      "_", i, ".tif"), overwrite = T)
    
    png(filename = paste0(models.dir, "/", sp, "/rf", sp, "_", i, "%03d.png"))
    plot(rf_cont, main = paste("RF raw", "\n", "AUC =", round(erf@auc, 2), "-", "TSS =", 
      round(rf_TSS, 2)))
    plot(rf_bin, main = paste("RF P/A", "\n", "AUC =", round(erf@auc, 2), "-", "TSS =", 
      round(rf_TSS, 2)))
    plot(rf_cut, main = paste("RF cut", "\n", "AUC =", round(erf@auc, 2), "-", "TSS =", 
      round(rf_TSS, 2)))
    dev.off()
    
    
    if (project.model == T) {
      for (proj in projections) {
        data <- list.files(paste0("./env/", proj), pattern = proj)
        data2 <- stack(data)
        rf_proj <- predict(data2, rf, progress = "text")
        rf_proj_bin <- rf_proj > thresholdrf
        rf_proj_cut <- rf_proj_bin * rf_proj
        # Normaliza o modelo cut rf_proj_cut <- rf_proj_cut/maxValue(rf_proj_cut)
        if (class(mask) == "SpatialPolygonsDataFrame") {
          source("./fct/cropModel.R")
          rf_proj <- cropModel(rf_proj, mask)
          rf_proj_bin <- cropModel(rf_proj_bin, mask)
          rf_proj_cut <- cropModel(rf_proj_cut, mask)
        }
        writeRaster(x = rf_proj, filename = paste0(models.dir, "/", sp, "/", 
          proj, "/rf_cont_", sp, "_", i, ".tif"), overwrite = T)
        writeRaster(x = rf_proj_bin, filename = paste0(models.dir, "/", sp, "/", 
          proj, "/rf_bin_", sp, "_", i, ".tif"), overwrite = T)
        writeRaster(x = rf_proj_cut, filename = paste0(models.dir, "/", sp, "/", 
          proj, "/rf_cut_", sp, "_", i, ".tif"), overwrite = T)
        rm(data2)
      }
    }
  }
  return(thrf)
}
