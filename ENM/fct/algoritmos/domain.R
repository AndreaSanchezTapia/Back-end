# coordinates: coordenadas para a espécie
# coordinates <- occs[occs$sp == sp, c("lon", "lat")]

# partitions: quantidade de partições
do_domain <- function(sp,
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
  cat(paste("Domain", "\n"))

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
  
#  if (! file.exists(file = paste0(models.dir, "/", sp, "/evaluate", sp, "_", i, ".txt"))) {
#    write.table(data.frame(kappa = numeric(), spec_sens = numeric(), no_omission = numeric(), prevalence = numeric(), 
#			         equal_sens_spec = numeric(), sensitivity = numeric(), AUC = numeric(), TSS = numeric(), algoritmo = character(), 
#				 partition = numeric()), file = paste0(models.dir, "/", sp, "/evaluate", sp, "_", i, ".txt"))
#  }
  
  ##### Hace los modelos
  for (i in unique(group)) {
    cat(paste(sp, "partition number", i, "\n"))
    pres_train <- coordinates[group != i, ]
    if (nrow(coordinates) == 1) 
      pres_train <- coordinates[group == i, ]
    pres_test <- coordinates[group == i, ]
    
    backg_test <- backgr[bg.grp == i, ]  #new
    
    do <- domain(predictors, pres_train)
    edo <- evaluate(pres_test, backg_test, do, predictors)
    thresholddo <- edo@t[which.max(edo@TPR + edo@TNR)]
    thdo <- threshold(edo)
    do_TSS <- max(edo@TPR + edo@TNR) - 1
    do_cont <- predict(predictors, do, progress = "text")
    do_bin <- do_cont > thresholddo
    do_cut <- do_cont * do_bin
    thdo$AUC <- edo@auc
    thdo$TSS <- do_TSS
    thdo$algoritmo <- "Domain"
    thdo$partition <- i
    row.names(thdo) <- paste(sp, i, "Domain")

    write.table(thdo, file = paste0(models.dir, "/", sp, "/evaluate", 
      sp, "_", i, "_domain.txt"))
    
    if (class(mask) == "SpatialPolygonsDataFrame") {
      source("../../fct/cropModel.R")
      do_cont <- cropModel(do_cont, mask)
      do_bin <- cropModel(do_bin, mask)
      do_cut <- cropModel(do_cut, mask)
    }
    writeRaster(x = do_cont, filename = paste0(models.dir, "/", sp, "/Domain_cont_", 
      sp, "_", i, ".tif"), overwrite = T)
    writeRaster(x = do_bin, filename = paste0(models.dir, "/", sp, "/Domain_bin_", 
      sp, "_", i, ".tif"), overwrite = T)
    writeRaster(x = do_cut, filename = paste0(models.dir, "/", sp, "/Domain_cut_", 
      sp, "_", i, ".tif"), overwrite = T)
    
    png(filename = paste0(models.dir, "/", sp, "/Domain", sp, "_", i, "%03d.png"))
    plot(do_cont, main = paste("Domain raw", "\n", "AUC =", round(edo@auc, 2), "-", 
      "TSS =", round(do_TSS, 2)))
    plot(do_bin, main = paste("Domain P/A", "\n", "AUC =", round(edo@auc, 2), "-", 
      "TSS =", round(do_TSS, 2)))
    plot(do_cut, main = paste("Domain cut", "\n", "AUC =", round(edo@auc, 2), "-", 
      "TSS =", round(do_TSS, 2)))
    dev.off()
  
  
    if (project.model == T) {
      for (proj in projections) {
        data <- list.files(paste0("./env/", proj), pattern = proj)
        data2 <- stack(data)
        do_proj <- predict(data2, do, progress = "text")
        do_proj_bin <- do_proj > thresholddo
        do_proj_cut <- do_proj_bin * do_proj
        # Normaliza o modelo cut do_proj_cut <- do_proj_cut/maxValue(do_proj_cut)
        if (class(mask) == "SpatialPolygonsDataFrame") {
          source("./fct/cropModel.R")
          do_proj <- cropModel(do_proj, mask)
          do_proj_bin <- cropModel(do_proj_bin, mask)
          do_proj_cut <- cropModel(do_proj_cut, mask)
        }
        writeRaster(x = do_proj, filename = paste0(models.dir, "/", sp, "/", 
          proj, "/Domain_cont_", sp, "_", i, ".tif"), overwrite = T)
        writeRaster(x = do_proj_bin, filename = paste0(models.dir, "/", sp, "/", 
          proj, "/Domain_bin_", sp, "_", i, ".tif"), overwrite = T)
        writeRaster(x = do_proj_cut, filename = paste0(models.dir, "/", sp, "/", 
          proj, "/Domain_cut_", sp, "_", i, ".tif"), overwrite = T)
        rm(data2)
      }
    }
  }
  return(thdo)
}
#    eval_df <- data.frame(kappa = 1, spec_sens = 1, no_omission = 1, prevalence = 1, 
#      equal_sens_spec = 1, sensitivity = 1, AUC = 1, TSS = 1, algoritmo = "foo", 
#      partition = 1)
#      eval_df <- rbind(eval_df, thdo)
