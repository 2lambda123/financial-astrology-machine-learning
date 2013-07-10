library(xts)
library(timeDate)
library(quantmod)
library(ggplot2)
#library(msProcess)
library(plyr)
library(data.table)
library(fields)
library(reshape2)
library(randomForest)
library(rpart)
library(evtree)
library(GA)
`%ni%` <- Negate(`%in%`)
# no scientific notation
options(scipen=100)
#options(error=recover)

planetsList <- list(c("SU", "SUR", "MO", "MOR", "ME", "MER", "VE", "VER", "MA", "MAR", "JU", "JUR", "SA", "SAR", "UR", "URR", "NE", "NER", "PL", "PLR"),
                    # combined fast planets
                    c("SU", "SUR", "MO", "MOR", "ME", "MER", "VE", "VER", "MA", "MAR"),
                    # combined slow planets
                    c("JU", "JUR", "SA", "SAR", "UR", "URR", "NE", "NER", "PL", "PLR"),
                    # trans jupiter
                    c("SA", "SAR", "UR", "URR", "NE", "NER", "PL", "PLR"),
                    # trans saturn
                    c("UR", "URR", "NE", "NER", "PL", "PLR"),
                    # all to radical
                    c("SUR", "MOR", "MER", "VER", "MAR", "JUR", "SAR", "URR", "NER", "PLR"),
                    # fast planets to radical
                    c("SUR", "MOR", "MER", "VER", "MAR"),
                    # slow planets to radical
                    c("JUR", "SAR", "URR", "NER", "PLR"),
                    # trans jupiter
                    c("SAR", "URR", "NER", "PLR"),
                    # trans saturn
                    c("URR", "NER", "PLR"),
                    # all planets to transit
                    c("SU", "MO", "ME", "VE", "MA", "JU", "SA", "UR", "NE", "PL"),
                    # fast planets
                    c("SU", "MO", "ME", "VE", "MA"),
                    # slow planets
                    c("JU", "SA", "UR", "NE", "PL"),
                    # trans jupiter
                    c("SA", "UR", "NE", "PL"),
                    # trans saturn
                    c("UR", "NE", "PL"),
                    # special combinations
                    c("SU", "SUR", "MO", "MOR", "ME", "MER", "VE", "VER"),
                    c("SU", "MO", "ME", "VE"),
                    c("SU", "SUR", "ME", "MER", "VE", "VER", "JU", "JUR"),
                    c("SU", "ME", "VE", "JU"),
                    c("SU", "SUR", "VE", "VER", "JU", "JUR"),
                    c("SU", "VE", "JU"),
                    c("MA", "MAR", "SA", "SAR", "UR", "URR", "NE", "NER", "PL", "PLR"),
                    c("MA", "SA", "UR", "NE", "PL"))

planetsCombList <- planetsList
#combn(planetsList[[1]], 5, simplify=FALSE))

aspectsList <- list(c('a0', 'a30', 'a45', 'a60', 'a72', 'a90', 'a120', 'a135', 'a144', 'a150', 'a180', 'a18', 'a40', 'a51', 'a80', 'a103', 'a108', 'a154', 'a160'),
                    c('a0', 'a45', 'a60', 'a90', 'a120', 'a150', 'a180'),
                    c('a0', 'a60', 'a90', 'a120', 'a180'),
                    c('a0', 'a30', 'a45', 'a60', 'a90', 'a120', 'a135', 'a150', 'a180'),
                    c('a30', 'a45', 'a72', 'a135', 'a144', 'a51', 'a103'),
                    c('a30', 'a45', 'a72', 'a135', 'a144', 'a18', 'a40', 'a51', 'a80', 'a103', 'a108', 'a154', 'a160'))

aspectsCombList <- aspectsList

# aspect types cols names
aspectTypesCols <- c('SUT', 'MOT', 'MET', 'VET', 'MAT', 'JUT', 'SAT', 'URT', 'NET', 'PLT')

# planets cols
planetsBaseCols <- c("SU", "MO", "ME", "VE", "MA", "JU", "SA", "UR", "NE", "PL", "NN", "SN")

# Aspects and orbs
aspects = c(0, 30, 45, 60, 72, 90, 120, 135, 144, 150, 180, 18, 40, 52, 80, 104, 108, 155, 160)
orbs    = c(3,  1,  1,  1,  1,  3,   3,   1,   1,   1,   3,  1,  1,  1,  1,   1,   1,   1,   1)

# planets columns names
planetsLonCols <- paste(planetsBaseCols, 'LON', sep='')
planetsLatCols <- paste(planetsBaseCols, 'LAT', sep='')
planetsSpCols <- paste(planetsBaseCols, 'SP', sep='')
planetsCombLon <- combn(planetsLonCols, 2, simplify=F)
planetsCombLonCols <- as.character(lapply(planetsCombLon, function(x) paste(x[1], x[2], sep='')))
planetsGridLon <- expand.grid(planetsLonCols, planetsLonCols)
planetsGridLonCols <- as.character(apply(planetsGridLon, 1, function(x) paste(x[1], 'r', x[2], sep='')))
planetsGridAspCols <- as.character(apply(expand.grid(planetsGridLonCols, aspects), 1, function(x) paste(x[1], '.', as.numeric(x[2]), sep='')))

# aspects types
aspectTypesList <- list(c('A', 'AE', 'SE', 'S'),
                        c('A', 'AE', 'SE'),
                        c('AE', 'SE'),
                        c('A', 'AE'),
                        c('SE', 'S'))

npath <- function(path) {
  normalizePath(path.expand(path))
}

# a function that returns the position of n-th largest
maxn <- function(x, n) {
  order_x <- order(x, decreasing = TRUE)
  if ( length(order_x) < n ) {
    n = length(order_x)
  }
  x[order_x[n]]
}

dsPlanetsData <- function(ds) {
  # remove observations that don't have enough market reaction (mondays with less than 12 hours)
  fds <- subset(ds, !(dayOfWeek(ds$endEffect) == 'Mon' & as.numeric(format(ds$endEffect, '%H')) < 12))
  # convert date as same format of planets days
  #fds$Date <- as.Date(as.character(fds$endEffect), format="%Y-%m-%d")
  # build new data frame with the important columns
  fds <- subset(fds, select=c("PT", "Date", "val", "PRLON"))
  # calculate effect in categorical type
  fds$effect = cut(fds$val, c(-1, 0, 1), labels=c('down', 'up'), right=FALSE)
  # merge planets and filtered data set
  fds <- merge(fds, planets.eur, by = "Date")
  # set an id
  fds$id <- as.numeric(rownames(fds))
  fds
}

dsPlanetsLon <- function(fds) {
  # planet transit name
  pt <- paste(fds[1,c('PT')], 'LON', sep='')
  start_degree <- fds[1,c(pt)]
  points.x <- unique(unlist(list(seq(start_degree, 0, by=-45), seq(start_degree, 360, by=45), seq(start_degree, 0, by=-30), seq(start_degree, 360, by=30))))
  angles <- data.frame(cbind(points.x, rep(-5, length(points.x))))
  names(angles) <- c('x', 'y')
  # reshape longitudes
  fds.lon <- reshape(fds, varying = c("SULON", "MOLON", "MELON", "VELON", "MALON", "JULON", "SALON", "URLON", "NELON", "PLLON", "NNLON", "SNLON", "PRLON"), v.names = "lon", times = c("SULON", "MOLON", "MELON", "VELON", "MALON", "JULON", "SALON", "URLON", "NELON", "PLLON", "NNLON", "SNLON", "PRLON"),  direction = "long")
  p1 <- ggplot(fds.lon, aes(x=lon, y=id, colour=time, shape=time, facet= . ~ effect)) + facet_grid(. ~ effect) + geom_point() + scale_x_continuous(breaks=seq(from=0, to=359, by=5), limits=c(0,359)) + scale_shape_manual("",values=c(1,2,3,4,5,6,7,8,9,10,11,12,13)) + coord_polar(start = 1.57, direction=-1) + scale_y_continuous(breaks = seq(-5, 15, 1), limits = c(-5, 15)) + theme_update(axis.text.x = theme_text(angle = -30, size = 6))
  p1 <- p1 + geom_segment(data = angles, aes(x = x, y = -5, xend = x, yend = 15), size = 0.2, show_guide = FALSE)
  p1 <- p1 + opts(panel.grid.major = theme_line(colour="grey", size=0.2), title='Longitudes down VS up')
  print(p1)
}

dsPlanetsLat <- function(fds) {

  minor_planets <- c("MOLAT", "MELAT", "VELAT", "MALAT", "JULAT")
  major_planets <- c("SALAT", "URLAT", "NELAT", "PLLAT")
  #p1 + geom_line(aes(y = c(8)), color = "yellow")
  # latitude
  fds.lat.min <- reshape(fds, varying = minor_planets, v.names = "lat", times = minor_planets, direction = "long")
  fds.lat.maj <- reshape(fds, varying = major_planets, v.names = "lat", times = major_planets, direction = "long")
  #p2 <- qplot(x=fds.lat$lat, y=fds.lat$id, colour=fds.lat$time, shape=fds.lat$time, data=fds.lat, geom='jitter') + scale_x_continuous(breaks=seq(from=-10, to=10, by=1)) + scale_shape_manual("",values=c(1,2,3,4,5,6,7,8,9,10)) + facet_grid(. ~ effect)
  # density
  p1 <- ggplot(fds.lat.min, aes(x = lat, fill=time)) + scale_x_continuous(breaks=seq(from=-10, to=10, by=1)) + geom_histogram(binwidth = 0.5) + facet_grid(effect ~ time) + opts(axis.text.x = theme_text(angle = -90, size = 6), axis.text.y = theme_text(angle = 0, size = 6))
  p1 <- p1 + labs(title = "Latitude Lower Planets")
  p2 <- ggplot(fds.lat.maj, aes(x = lat, fill=time)) + scale_x_continuous(breaks=seq(from=-10, to=10, by=1)) + geom_histogram(binwidth = 0.5) + facet_grid(effect ~ time) + opts(axis.text.x = theme_text(angle = -90, size = 6), axis.text.y = theme_text(angle = 0, size = 6))
  p2 <- p2 + labs(title = "Latitude Major Planets")
  print(p1)
  print(p2)
}

dsPlanetsSpeed <- function(fds) {
  # speed
  slow_planets <- c("SASP", "URSP", "NESP", "PLSP")
  fast_planets <- c("MESP", "VESP", "MASP", "JUSP", "SASP")
  extra_planets <- c("MOSP")
  fds.sp.fast <- reshape(fds, varying = fast_planets, v.names = "speed", times = fast_planets, direction = "long")
  fds.sp.slow <- reshape(fds, varying = slow_planets, v.names = "speed", times = slow_planets, direction = "long")
  fds.sp.extra <- reshape(fds, varying = extra_planets, v.names = "speed", times = extra_planets, direction = "long")

  p1 <- ggplot(fds.sp.slow, aes(x = speed, fill=time)) + scale_x_continuous(breaks=seq(from=-0.3, to=0.3, by=0.01)) + geom_histogram(binwidth = 0.005) + facet_grid(effect ~ time)
  p1 <- p1 + opts(axis.text.x = theme_text(angle = -90, size = 6), axis.text.y = theme_text(angle = 0, size = 6), title = 'Speed Major Planets down VS up')
  p2 <- ggplot(fds.sp.fast, aes(x = speed, fill=time)) + scale_x_continuous(breaks=seq(from=-1, to=2, by=0.2)) + geom_histogram(binwidth = 0.1) + facet_grid(effect ~ time)
  p2 <- p2 + opts(axis.text.x = theme_text(angle = -90, size = 6), axis.text.y = theme_text(angle = 0, size = 6), title = 'Speed Minor Planets down VS up')
  p3 <- ggplot(fds.sp.extra, aes(x = speed, fill=time)) + scale_x_continuous(breaks=seq(from=9, to=16, by=0.5)) + geom_histogram(binwidth = 0.5) + facet_grid(effect ~ time)
  p3 <- p3 + opts(axis.text.x = theme_text(angle = -90, size = 6), axis.text.y = theme_text(angle = 0, size = 6), title = 'Speed Moon down VS up')
  print(p1)
  print(p2)
  print(p3)
}

dsPlanetsReport <- function(ds, data_name, kplanets, kaspects) {
  dsasp <- reshape(ds, varying = kplanets, v.names = "aspect", times = kplanets,  direction = "long")
  # select only the aspects to consider
  dsasp <- subset(dsasp, aspect %in% kaspects)
  dsasp$aspect <- factor(dsasp$aspect)
  ds_up <- data.table(subset(dsasp, Eff=='up'))
  ds_down <- data.table(subset(dsasp, Eff=='down'))
  tup <- as.data.frame(ds_up[, as.list(table(aspect)), by = c('idx')])
  tdown <- as.data.frame(ds_down[, as.list(table(aspect)), by = c('idx')])
  tablediff <- abs(tup[,-1]-tdown[,-1])
  qtile <- as.numeric(quantile(tablediff[,tablediff[,] > 0])[3])
  diffcols <- colnames(tablediff[,tablediff >= qtile])
  tup[!colnames(tup) %in% diffcols] <- 0
  tdown[!colnames(tup) %in% diffcols] <- 0
  tupdown <- t(rbind(tup, tdown))[-1,]
  colnames(tupdown) <- c('tup', 'tdown')
  tup <- apply(tupdown, 1, function(x) ifelse(x[1] > x[2], 1, 0))
  tdown <- apply(tupdown, 1, function(x) ifelse(x[2] > x[1], 1, 0))
  tupdown <- t(tupdown)
  tupdown2 <- rbind(tup, tdown)
  print(tupdown)
  print(tupdown2)
  #dis1 <- dist(rbind(tupdown2[1,], asptable), method="canberra")
  #dis2 <- dist(rbind(tupdown2[2,], asptable), method="canberra")
  #effect <- ifelse(dis1 < dis2, ifelse(dis1 != dis2, 'up', 'none'), 'down')
  #writeLines("UP aspects table")
  #writeLines("DOWN aspects table")

  fds <- dsPlanetsData(ds)
  pdf("~/plots.pdf", width = 11, height = 8, family='Helvetica', pointsize=12)
  plot(0:10, type = "n", xaxt="n", yaxt="n", bty="n", xlab = "", ylab = "")
  report_title <- paste("Chart ", data_name, " : ", ds[1,c('PT')], " ", ds[1,c('AS')], " ", ds[1,c('PR')])
  text(5, 10, report_title)
  obs_dates <- paste(fds[,c('Date')], collapse='\n')
  text(5, 4, obs_dates)
  # chart the hourly currency price for each date
  chart_dates = paste(fds$Date, fds$Date, sep="/")
  for (j in 1:length(chart_dates)) {
    if (nrow(eurusd.hour.xts[chart_dates[j]]) == 24) {
      chartSeries(eurusd.hour.xts, subset=chart_dates[j], major.ticks='hours', show.grid=TRUE, theme='white.mono')
    }
  }
  p1 <- qplot(data=fds, x=val, binwidth=0.0025) + scale_x_continuous(breaks=seq(from=-0.05, to=0.05, by=0.0025))
  dsPlanetsLon(fds)
  dsPlanetsLat(fds)
  dsPlanetsSpeed(fds)
  dev.off()
}

dsAspectTable <- function(ds, keys) {
  dsasp <- reshape(ds, varying = keys, v.names = "aspect", times = keys,  direction = "long")
  sapply(table(dsasp$aspect), function(x) ifelse(x > 0, 1, x))
}

decToDeg <- function(num) {
  num <- abs(num)
  d <- as.integer(num)
  part <- (num-d)*60
  m <- as.integer(part)
  s <- as.integer((part-m)*60)
  c(d, m, s)
}

fivePastDays <- function(x) {
  unique(paste(as.Date(index(x)) - 5, as.Date(index(x), format="%Y%m%d"), sep = "/"))
}

hourlyValue <- function(dataset, bhours, ahours) {
  results = array()
  for (j in 1:nrow(dataset)) {
    tbl = sapply(eurusd.hour.xts[paste(dataset[j,]$endEffect-3600*bhours, dataset[j,]$endEffect+3600*ahours, sep='/')], sum)
    results[j] <- tbl['val']
  }
  results
}

planetAspectsEffect <- function(ptcode, pacode, pacodet) {
  #ds = subset(eurusd.merged, eval(conditions))
  conditions = expression(PT == ptcode & get(pacode) %in% c('a12', 'a9', 'a6', 'a180', 'a0') & get(pacodet) %in% c('A', 'AE'))
  ds = subset(eurusd.merged, eval(conditions))
  ds$val = round(hourlyValue(ds, 5, 1), digits=4)
  p = qplot(get(pacode), val, data=ds, geom='boxplot')
  p + geom_hline(yintercept=c(0.007, 0.005, 0, -0.005, -0.007))
}

# trans.xts[fivePastDays(trans.xts['20121022'])]
# index(trans.xts)

openCurrency  <- function(currency_file) {
  currency_file <- npath(currency_file)
  currency <- read.table(currency_file, header = T, sep=",")
  names(currency) <- c('Ticker', 'Date', 'Time', 'Open', 'Low', 'High', 'Close')
  currency <- currency[,-1]
  #currency$Mid <- (currency$High + currency$Low + currency$Close) / 3
  currency$Mid <- (currency$High + currency$Low + currency$Close + currency$Open) / 4
  currency$val <- currency$Mid - currency$Open
  currency$Eff = cut(currency$val, c(-1, 0, 1), labels=c('down', 'up'), right=FALSE)
  currency$Date <- as.Date(as.character(currency$Date), format="%Y%m%d")
  currency
}

openCommodity <- function(currency_file) {
  currency_file <- npath(currency_file)
  currency <- read.table(currency_file, header = F, sep=",")
  names(currency) <- c('Date', 'Time', 'Open', 'High', 'Low', 'Close', 'Volume')
  currency <- currency[,-7]
  currency$Mid <- (currency$High + currency$Low + currency$Close + currency$Open) / 4
  currency$val <- currency$Mid - currency$Open
  #currency$val <- currency$Close - currency$Mid
  currency$Eff = cut(currency$val, c(-1, 0, 1), labels=c('down', 'up'), right=FALSE)
  currency$Date <- as.Date(as.character(currency$Date), format="%Y.%m.%d")
  currency
}

openCurrencyXts <- function(currency_file) {
  currency_file <- npath(currency_file)
  currency <- openTrans(currency_file)
  xts(currency[,-1:-2], order.by=currency[,1])
}

removeAspectsOutType <- function(X, asptype) {
  Y <- X[1:20]
  v <- X[21:30] %in% asptype
  # double the validation vector intercalating elements
  v <- c(matrix(c(v,v), 2, byrow=T))
  Y <- ifelse(v, Y, NA);
  Y
}

# Open a Transits table and merge with a currency table
openTrans <- function(trans_file, effcorrection=0, hourcorrection=7) {
  trans_file <- npath(trans_file)
  # transits
  trans <- fread(trans_file, header = T, sep="\t", na.strings = "", verbose = FALSE)
  trans[, Date := as.Date(Date, format="%Y-%m-%d")]
  trans[, S2 := S+SUS+MOS+MES+VES+JUS+SAS+URS+NES+PLS]
  #timeEffect <- strptime(trans$endEffect, format="%Y-%m-%d %H:%M:%S", tz="UTC")
  # timeDate automatically correct summer time based on the rules of the financial center
  timeEffect <- timeDate(paste(trans$Date, trans$Hour), format = "%Y-%m-%d %H:%M:%S", zone = "UTC", FinCenter = "Europe/Bucharest")
  trans[, endEffect := as.character(timeEffect)]
  trans[, WD := format(timeEffect, "%w")]
  trans[, H := as.numeric(format(timeEffect, "%H"))]
  # remove the slow planets transits and other points that complicate prediction
  trans <- trans[PT %ni% c('MO', 'JU', 'SA', 'UR', 'NE', 'PL') & PR %ni% c('Asc', 'MC')]

  if (effcorrection) {
    # substract one day to the aspects tha are early in the day
    # the effect should be produced the previous day
    trans[, Date := as.double(strptime(Date, "%Y-%m-%d"))]
    trans[, Date := as.Date(as.POSIXlt(ifelse(H <= hourcorrection, Date-86400, Date), origin="1970-01-01"), format="%Y-%m-%d")]
  }

  # replace NA aspects by none due randomForest need a value
  trans[, planetsList[[1]] := lapply(.SD, function(x) ifelse(is.na(x), 'none', x)), .SDcols=planetsList[[1]]]
  # set as factors
  trans[, planetsList[[1]] := lapply(.SD, as.factor), .SDcols=planetsList[[1]]]

  # Convert the riseset times to correct timezone for Cyprus
  #tzcorrect <- format(as.POSIXlt(paste(trans$Date, trans$ASC1), format = "%Y-%m-%d %H:%M") + 3600 * 2.5, "%H:%M")
  #trans$ASC1 <- tzcorrect
  trans[, PC := trans$PT]
  trans[, PC := factor(trans$PC, levels = c('SU', 'MO', 'ME', 'VE', 'MA', 'JU', 'SA', 'UR', 'NE', 'PL'), labels = c(0, 1, 2, 3, 4, 5, 6, 7, 8, 9))]
  # give each transit type an index
  trans[, idx := paste(PT, AS, PR, SI, sep='')]
  trans[, idx2 := paste(Date, PT, AS, PR, SI, sep='')]
  return(as.data.frame(trans))
}

openTransXts <- function(trans_file) {
  trans <- openTrans(trans_file)
  # remove the time column
  trans_xts <- xts(trans[,-2], order.by=trans$Date)
  trans_xts
}

# build merged table for currency and transits
mergeTrans <- function(ds_trans, currency_table) {
  trans.price = merge(currency_table, ds_trans, by = "Date")
  trans.price[, !(names(trans.price) %in% c("Time", "Hour"))]
}

predictTrend <- function(search_date) {
  date_date <- as.Date(as.character(search_date), format="%Y-%m-%d")
  chart_dates = paste(date_date-1, date_date, sep="/")
  ds <- trans.eur[search_date]
  print(ds)
  hisds <- subset(trans.eurusd.eur, idx %in% ds$idx)
  print(prop.table(table(hisds$Eff)))
  chartSeries(eurusd.hour.xts, subset=chart_dates, major.ticks='hours', show.grid=TRUE, theme='white.mono')
}

predColNames = c('Date', 'idx', 'idx2', 'endEffect', 'S2', 'PC', 'SUR', 'SURD', 'MOR', 'MORD', 'MER', 'MERD', 'VER', 'VERD', 'MAR', 'MARD', 'JUR', 'JURD', 'SAR', 'SARD', 'URR', 'URRD', 'NER', 'NERD', 'PLR', 'PLRD', 'udis', 'ddis', 'corEff', 'ucor', 'dcor')

predictTransTable <- function(trans, trans.hist, cor_method, kplanets, kaspects, binarize=1, rmzeroaspects=1, qinmode='q3', maxasp=2) {
  # convert to data table
  trans.hist <- data.table(trans.hist)
  trans <- data.table(trans)
  setkey(trans, 'Date', 'idx')
  # generate the count effect table
  #predict_table <- predictAspectsTable(trans.hist)
  selected <- trans[, idx[which(S2 >= maxn(S2, maxasp))], by=c('Date')]
  setnames(selected, 'V1', 'idx')
  # get the aspects correlation table
  aspect_dates_cor <- historyAspectsCorrelation(trans, trans.hist, cor_method, kplanets, kaspects, binarize, rmzeroaspects, qinmode)
  # merge
  #aspect_dates_predict <- merge(selected, predict_table, by='idx')
  predict.table <- merge(selected, trans, by=c('Date', 'idx'))
  predict.table <- merge(predict.table, aspect_dates_cor, by=c('Date', 'idx'))
  # sort and return
  predict.table <- arrange(predict.table, desc(Date))
  predict.table <- as.data.frame(predict.table)
  predict.table[predColNames]
}

predictTransTableWrite <- function(trans, trans.hist, cor_method, kplanets, kaspects, binarize, rmzeroaspects, qinmode, filename) {
  aspect_dates_predict <- predictTransTable(trans, trans.hist, cor_method, kplanets, kaspects, binarize, rmzeroaspects, qinmode, 2)
  write.csv(aspect_dates_predict[predColNames], file=npath(paste("~/trading/predict/", file_name, sep='')), eol="\r\n", quote=FALSE, row.names=FALSE)
}

predictSingleTransTable <- function(ds, ds_hist, file_name) {
  ds <- as.data.frame(ds)
  ds_count <- data.frame(tapply(1:NROW(ds), ds$Date, function(x) length(unique(x))))
  names(ds_count) <- c('Count')
  filter_dates <- rownames(subset(ds_count, Count==1))
  # access a date with ndist['2014-12-29',]
  single_aspect_dates <- subset(ds, select=c('Date', 'idx', 'endEffect', 'WD', 'S2', 'SU', 'MO', 'ME', 'VE', 'MA', 'JU', 'SA', 'UR', 'NE', 'PL'), Date %in% filter_dates)
  single_aspect_dates <- as.data.frame(single_aspect_dates, row.names=1:nrow(single_aspect_dates))
  aspects_effect <- predictAspectsTable(ds_hist)
  #aspect_val_mean <- tapply(ds$val, ds$idx, mean)
  aspect_dates_predict <- merge(single_aspect_dates, aspects_effect, by='idx')
  # sort by date
  aspect_dates_predict <- arrange(aspect_dates_predict, desc(Date))
  # round the val mean
  write.csv(aspect_dates_predict[c(2, 12:14, 3:11, 1)], file=npath(paste("~/trading/predict/", file_name, sep='')), eol="\r\n", quote=FALSE, row.names=FALSE)
}

predictAspectsTable <- function(ds_hist) {
  ds_hist <- ds_hist[,c('idx', 'Eff'), with=FALSE]
  setkey(ds_hist, 'idx')
  #predict_table <- ddply(ds_hist, .(idx), summarize, down=table(Eff)[['down']], up=table(Eff)[['up']], count=length(Eff))
  predict_table <- ds_hist[,as.list(table(Eff)), by=c('idx')]
  predict_table <- predict_table[,count:=down+up]
  predict_table
}

filterZeroAspects <- function(X) {
  init1 <- 1
  end1 <- length(X)/3
  init2 <- end1+1
  end2 <- end1*2
  init3 <- end2+1
  end3 <- end1*3
  X1 <- X[init1:end1]
  X2 <- X[init2:end2]
  X3 <- X[init3:end3]
  X1 <- ifelse(X2 == 0 & X3 == 0, 0, X1)
}

completeAspectList <- function(X, kaspects) {
  missidx <- kaspects[kaspects %ni% names(X)]
  X[missidx] <- 0
  X
}

historyAspectsCorrelation <- function(trans, trans.hist, cor_method, kplanets, kaspects, binarize=1, rmzeroaspects=1, qinmode='q3') {
  if (qinmode %ni% c('q1', 'q2', 'q3', 'q4', 'q5')) stop("Provide a valid value for qinmode")
  #remove no needed cols to save memory
  trans <- trans[,c('Date', 'idx', kplanets), with=FALSE]
  trans.hist <- trans.hist[,c('Date', 'idx', 'Eff', kplanets), with=FALSE]
  # melt return a data.frame so we need to convert to data.table
  dsasp <- data.table(melt(trans.hist, id.var=c('Date', 'idx', 'Eff'), measure.var=kplanets))
  setnames(dsasp, c('Date', 'idx', 'Eff', 'planet', 'aspect'))
  setkey(dsasp, 'Date', 'idx', 'Eff', 'aspect')
  # select only the aspects to consider
  dsasp <- dsasp[aspect %in% kaspects]
  # adjust factor levels
  dsasp$aspect <- factor(dsasp$aspect)
  # separate the up/down tables
  dsup <- dsasp[Eff=='up']
  dsdown <- dsasp[Eff=='down']
  # build up/down aspect tables
  dsup <- dsup[, as.list(completeAspectList((table(aspect)), kaspects=kaspects)), by = c('idx')]
  ucolnames <- paste(names(dsup)[2:length(names(dsup))], 'u', sep='.')
  setnames(dsup, c('idx', ucolnames))
  dsdown <- dsdown[, as.list(completeAspectList((table(aspect)), kaspects=kaspects)), by = c('idx')]
  dcolnames <- paste(names(dsdown)[2:length(names(dsdown))], 'd', sep='.')
  # before set dcolnames build the substract colnames
  scolnames <- paste(names(dsdown)[2:length(names(dsdown))], 's', sep='.')
  setnames(dsdown, c('idx', dcolnames))
  # merge_recurse(apply(trans[,kplanets], 2, function(x) count(x)))
  # by(trans.eur[,kplanets], trans.eur$idx, function(x) { table(apply(x, 1, function(x) x)) })
  # reshape the transits data and generate aspect table
  dscurrent <- data.table(melt(trans, id.var=c('Date','idx'), measure.var=kplanets))
  setnames(dscurrent, c('Date', 'idx', 'planet', 'aspect'))
  # select only the aspects to consider
  dscurrent <- dscurrent[aspect %in% kaspects]
  # adjust factor levels
  dscurrent$aspect <- factor(dscurrent$aspect)
  setkey(dscurrent, 'Date', 'idx', 'aspect')
  dscurrent <- dscurrent[, as.list(completeAspectList((table(aspect)), kaspects=kaspects)), by = c('Date','idx')]
  ccolnames <- paste(names(dscurrent)[3:length(names(dscurrent))], 'c', sep='.')
  setnames(dscurrent, c('Date', 'idx', ccolnames))

  # merge
  predtable <- merge(dscurrent, dsup, by='idx')
  predtable <- merge(predtable, dsdown, by='idx')
  #predtable <- Reduce('merge', list(dscurrent, dsup, dsdown))
  # number of aspects
  naspects <- length(kaspects)
  # the first two cols are date and indx
  initcol <- 3
  # selected cols
  cols1 <- seq(initcol, naspects+initcol-1)
  cols2 <- cols1 + naspects
  cols3 <- cols2 + naspects

  predtable[,scolnames] = abs(predtable[,cols2,with=FALSE]-predtable[,cols3,with=FALSE])
  # set zero cols to NA for each column via data.table
  for (colname in scolnames) {
    expr1 <- parse(text = paste(colname, "== 0"))
    expr2 <- parse(text = paste(colname, ":= NA"))
    predtable[eval(expr1), eval(expr2)]
  }

  # build expression to generate quantile based on the diff cols
  expr1 <- parse(text = paste('as.list(quantile(c(',paste(scolnames, collapse=","),'), na.rm=TRUE))',sep=''))
  qtiles <- predtable[,eval(expr1),by=c('Date','idx')]
  setnames(qtiles, c('Date', 'idx', 'q1', 'q2', 'q3', 'q4', 'q5'))
  predtable  <- merge(predtable, qtiles, by=c('Date','idx'))

  # set all the columns that are less that qintile to 0
  for (i in 1:naspects) {
    expr1 <- parse(text = paste(scolnames[[i]], "<", qinmode, '| is.na(', scolnames[[i]], ')'))
    expr2 <- parse(text = paste(ucolnames[[i]], ":= 0"))
    expr3 <- parse(text = paste(dcolnames[[i]], ":= 0"))
    predtable[eval(expr1), eval(expr2)]
    predtable[eval(expr1), eval(expr3)]
  }

  # leave the major value between up/downs
  for (i in 1:naspects) {
    # up greater that down, reset down
    expr1 <- parse(text = paste(ucolnames[[i]], ">", dcolnames[[i]]))
    expr2 <- parse(text = paste(dcolnames[[i]], ":= 0"))
    predtable[eval(expr1), eval(expr2)]
    # down greater than up, reset up
    expr1 <- parse(text = paste(dcolnames[[i]], ">", ucolnames[[i]]))
    expr2 <- parse(text = paste(ucolnames[[i]], ":= 0"))
    predtable[eval(expr1), eval(expr2)]
  }

  # deprecated by above approach
  #predtable[,c(cols2,cols3)] <- t(apply(predtable[,c(cols2,cols3)], 1, filterLessSignificant, qinmode=qinmode))

  # convert to data frame
  predtable <- as.data.frame(predtable)

  if (rmzeroaspects) {
    predtable[,cols1] <- t(apply(predtable[,c(cols1,cols2,cols3)], 1, filterZeroAspects))
  }

  if (binarize) {
    # set active aspects to 1 so correlation fits better
    predtable[,c(cols1,cols2,cols3)] <- apply(predtable[,c(cols1,cols2,cols3)], 2, function(x) ifelse(x > 0, 1, x))
  }

  #predtable[,cols2] <- t(apply(predtable[,cols2], 1, function(x) ifelse(x >= x[which.max(x)]/3, 1, 0)))
  #predtable[,cols3] <- t(apply(predtable[,cols3], 1, function(x) ifelse(x >= x[which.max(x)]/3, 1, 0)))
  predtable$udis <- apply(predtable, 1, function(x) dist(rbind(x[cols1], x[cols2]), method=cor_method))
  predtable$ddis <- apply(predtable, 1, function(x) dist(rbind(x[cols1], x[cols3]), method=cor_method))
  # TODO: if all(c(cols1, cols2) == 0) then udis/ddis/corEff = NA we can't predict it
  predtable$corEff <- apply(predtable[,c('udis','ddis')], 1, function(x) ifelse(x[1] != x[2], ifelse(x[1] < x[2], 'up', 'down'), NA))
  predtable$ucor <- round(apply(predtable[,c(cols1, cols2, cols3)], 1, function(x) cor(x[cols1-2], x[cols2-2], method='pearson')), digits=2)
  predtable$dcor <- round(apply(predtable[,c(cols1, cols2, cols3)], 1, function(x) cor(x[cols1-2], x[cols3-2], method='pearson')), digits=2)

  data.table(predtable)
}

openPlanets <- function(planets.file, chart, cusorbs) {
  planets.file <- npath(planets.file)
  planets <- fread(planets.file, sep="\t", na.strings="", verbose = F)
  planets$Date <- as.Date(planets$Date, format="%Y-%m-%d")

  # calculate longitudinal differences
  for (i in 1:length(planetsCombLon)) {
    combname <- paste(planetsCombLon[[i]][1], planetsCombLon[[i]][2], sep='')
    planets[, c(combname) := diffDeg(get(planetsCombLon[[i]][1]), get(planetsCombLon[[i]][2]), orbs)]
  }

  if (hasArg('chart')) {
    if (hasArg('cusorbs')) orbs <- cusorbs
    if (length(cusorbs) != length(orbs)) {
      stop("There are missing custom orbs")
    }
    for (i in 1:nrow(planetsGridLon)) {
      chartCol  <- as.character(planetsGridLon[i,1])
      planetsCol <- as.character(planetsGridLon[i,2])
      combname <- paste(chartCol, 'r', planetsCol, sep='')
      planets[, c(combname) := diffDeg(get(planetsCol), chart[[chartCol]][1], orbs)]
      for (j in 1:length(aspects)) {
        combnameasp <- c(paste(combname, '.', aspects[j], sep=''))
        # initialize
        planets[, c(combnameasp) := NA]
        # set to 1 the matching rows
        planets[get(combname)==aspects[j], c(combnameasp) := 1]
      }
    }
  }

  return(planets)
}

funtionizethis  <- function() {
  # hourly rate history
  eurusd.hour <- read.table("~/trading/EURUSD_hour.csv", header = T, sep=",")
  names(eurusd.hour) <- c('Ticker', 'Date', 'Time', 'Open', 'Low', 'High', 'Close')
  eurusd.hour <- eurusd.hour[,-1]
  eurusd.hour$val <- eurusd.hour$Close - eurusd.hour$Open
  eurusd.hour$Date <- timeDate(paste(eurusd.hour$Date, eurusd.hour$Time), format = "%Y%m%d %H:%M:%S", zone = "CET", FinCenter = "CET")
  eurusd.hour.xts <- xts(eurusd.hour[,-1:-2], order.by=eurusd.hour[,1])

  # euro usd currency daily
  eurusd_full <- openCurrency("~/trading/EURUSD_day.csv")
  #eurusd <- openCommodity("~/trading/")
  # usd cad currency daily
  usdcad <- openCurrency("~/trading/USDCAD_day.csv")
  # transits USD chart
  trans.usa = openTrans("~/trading/transits_usa/USA_1997-2014_trans_orb1.tsv")
  trans.usa2 = openTrans("~/trading/transits_usa/USA_coinage_1997-2014_trans_orb1.tsv")
  # transits EUR chart
  # transits CAD chart
  trans.cad <- openTransXts("~/trading/1990-2015_trans_CAD.tsv")
  # test trans
  trans.test <- openTransXts("~/trading/transits_eur/test.tsv")
  # currency - transits EURUSD
  trans.eurusd.usa  <- mergeTrans(trans.usa, eurusd)
  trans.eurusd.usa2  <- mergeTrans(trans.usa2, eurusd)
  # currency - transits USDCAD
  trans.usdcad.usa  <- mergeTrans(trans.usa, usdcad)

  planets.eur <- read.table("~/trading/EUR_2000-2014_planets_20130518.tsv", header = T, sep="\t")
  planets.eur$Date <- as.Date(planets.eur$Date, format="%Y-%m-%d")
  write.csv(planets.eur, file=paste("~/mt4/planets1.csv", sep=''), eol="\r\n", quote=FALSE, row.names=FALSE)

  planets.usa <- read.table("~/trading/USA_2012_2014_planets_20130503.tsv", header = T, sep="\t")
  planets.usa$Date <- as.Date(planets.usa$Date, format="%Y-%m-%d")
  write.csv(planets.usa, file=paste("~/mt4/planets2.csv", sep=''), eol="\r\n", quote=FALSE, row.names=FALSE)

  #mars.jupiter[order(venus.jupiter$val)]
  eurusd.aggregated = aggregate(trans.price.eur$val, list(Ptran = trans.price.eur$Ptran, Aspect = trans.price.eur$Aspect, Prad = trans.price.eur$Prad, Sign = trans.price.eur$Sign), mean)
  # rename sex by sextil
  Aspect = gsub('sex', 'sextil', Aspect)
  # split string
  # strsplit(Aspect, 'x')
  # remove rows with missing variables
  # na.omit(sun.neptune)

  # system time
  nowDate = Sys.time()
  # exctract individual components of date
  wkday = weekdays(nowDate)
  month = months(nowDate)
  quarter = quarters(nowDate)

  # Calculate the moving average with a window of 10 points
  mov.avg <- ma(values, 1, 10, FALSE)

  ## calculate peaks and valleys
  currency.planets = merge(usdcad, planets, by = "Date")
  a <- currency.planets$Open
  ## detect local maxima and minima
  maxmin <- msExtrema(a, 50)
  ## visualize the result
  par(mfrow=c(1,1))
  plot(a, type="l")
  points((1:length(a))[maxmin$index.max],
         a[maxmin$index.max], col=2, pch=1)
  points((1:length(a))[maxmin$index.min],
         a[maxmin$index.min], col=3, pch=2)
  if (!is.R()){
    legend(x=18, y=3, col=2:3, marks=1:2, legend=c("maxima", "minima"))
  } else {
    legend(x=18, y=3, col=2:3, pch=1:2, legend=c("maxima", "minima"))
  }

  currency.max <- currency.planets[maxmin$index.max,]
  currency.min <- currency.planets[maxmin$index.min,]

  # max reshape by longitude
  l.max <- reshape(currency.max, varying = c("SULON", "MOLON", "MELON", "VELON", "MALON", "JULON", "SALON"), v.names = "lon", times = c("SULON", "MOLON", "MELON", "VELON", "MALON", "JULON", "SALON"),  direction = "long")
  #p2 <- ggplot(l.max, aes(x=lon, y=10, colour=time, shape=time)) + scale_x_continuous(breaks=seq(from=0, to=360, by=5)) + coord_polar(start = 1.57, direction=1) + scale_shape_manual("",values=c(1,2,3,4,5,6,7,8,9,10)) +  geom_jitter(position = position_jitter(height = .5))
  p2 <- qplot(y=l.max$lon, colour=l.max$time, shape=l.max$time) + scale_y_continuous(breaks=seq(from=1, to=360, by=10)) + scale_shape_manual("",values=c(1,2,3,4,5,6,7,8,9,10))

  # max reshape by latitude
  l.max.lat <- reshape(currency.max, varying = c("SULAT", "MOLAT", "MELAT", "VELAT", "MALAT", "JULAT", "SALAT", "URLAT", "NELAT", "PLLAT"), v.names = "lat", times = c("SULAT", "MOLAT", "MELAT", "VELAT", "MALAT", "JULAT", "SALAT", "URLAT", "NELAT", "PLLAT"),  direction = "long")
  p2 <- qplot(y=l.max.lat$lat, colour=time, shape=time, data=l.max.lat) + scale_y_continuous(breaks=seq(from=-10, to=10, by=2)) + scale_shape_manual("",values=c(1,2,3,4,5,6,7,8,9,10))

  # max reshape by speed
  l.max.sp <- reshape(currency.max, varying = c("SUSP", "MOSP", "MESP", "VESP", "MASP", "JUSP", "SASP", "URSP", "NESP", "PLSP"), v.names = "speed", times = c("SUSP", "MOSP", "MESP", "VESP", "MASP", "JUSP", "SASP", "URSP", "NESP", "PLSP"),  direction = "long")
  p2 <- qplot(y=l.max.sp$speed, colour=time, shape=time, data=l.max.sp) + scale_y_continuous(breaks=seq(from=-1, to=1.3, by=0.05), limits=c(-1,1.5)) + scale_shape_manual("",values=c(1,2,3,4,5,6,7,8,9,10))

  # min reshape by longitude
  l.min <- reshape(currency.min, varying = c("SULON", "MOLON", "MELON", "VELON", "MALON", "JULON", "SALON"), v.names = "lon", times = c("SULON", "MOLON", "MELON", "VELON", "MALON", "JULON", "SALON"),  direction = "long")
  p1 <- qplot(y=l.min$lon, colour=l.min$time, shape=l.min$time) + scale_y_continuous(breaks=seq(from=1, to=360, by=10)) + scale_shape_manual("",values=c(1,2,3,4,5,6,7,8,9,10))

  # min reshape by longitude
  l.min.lat <- reshape(currency.min, varying = c("SULAT", "MOLAT", "MELAT", "VELAT", "MALAT", "JULAT", "SALAT", "URLAT", "NELAT", "PLLAT"), v.names = "lat", times = c("SULAT", "MOLAT", "MELAT", "VELAT", "MALAT", "JULAT", "SALAT", "URLAT", "NELAT", "PLLAT"),  direction = "long")
  p1 <- qplot(y=l.min.lat$lat, colour=l.min.lat$time, shape=l.min.lat$time) + scale_y_continuous(breaks=seq(from=-10, to=10, by=2)) + scale_shape_manual("",values=c(1,2,3,4,5,6,7,8,9,10))

  # min reshape by speed
  l.min.sp <- reshape(currency.min, varying = c("SUSP", "MOSP", "MESP", "VESP", "MASP", "JUSP", "SASP", "URSP", "NESP", "PLSP"), v.names = "speed", times = c("SUSP", "MOSP", "MESP", "VESP", "MASP", "JUSP", "SASP", "URSP", "NESP", "PLSP"),  direction = "long")
  p1 <- qplot(y=l.min.sp$speed, colour=l.min.sp$time, shape=l.min.sp$time) + scale_y_continuous(breaks=seq(from=-1, to=1.3, by=0.05), limits=c(-1,1.5)) + scale_shape_manual("",values=c(1,2,3,4,5,6,7,8,9,10))

  # density plot
  p1 <- ggplot(l.min, aes(x = l.min$lon)) + scale_x_continuous(breaks=seq(from=0, to=360, by=5), limits=c(0,360)) + geom_density(adjust=1/12) + coord_polar(start = 1.57, direction=-1) + theme_update(axis.text.x = theme_text(angle = -30, size = 6))
  p2 <- ggplot(l.max, aes(x = l.max$lon)) + scale_x_continuous(breaks=seq(from=0, to=360, by=5), limits=c(0,360)) + geom_density(adjust=1/12) + coord_polar(start = 1.57, direction=-1) + theme_update(axis.text.x = theme_text(angle = -30, size = 6))

  vplayout <- function(x, y) viewport(layout.pos.row = x, layout.pos.col = y)
  grid.newpage()
  pushViewport(viewport(layout = grid.layout(1, 2)))
  print(p1, vp = vplayout(1, 1))
  print(p2, vp = vplayout(1, 2))

  d <- ggplot(l, aes(x = lon))
  d + geom_density(adjust=5)

  d + geom_density2d()
  d + scale_colour_hue("clarity")
  d + scale_colour_hue(expression(clarity[beta]))

  # Adjust luminosity and chroma
  d + scale_colour_hue(l=40, c=30)
  d + scale_colour_hue(l=70, c=30)
  d + scale_colour_hue(l=70, c=150)
  d + scale_colour_hue(l=80, c=150)

  # Change range of hues used
  d + scale_colour_hue(h=c(0, 360, l=100, c=200))

  ggplot(filld, aes(xmin = start, xmax = end, ymin = 4, ymax = 5, fill = label)) + geom_rect() + geom_segment(aes(x = 4, y = 0, xend = 4, yend = 5, colour = label), size = 2, show_guide = FALSE) + geom_text(aes(x = p, y = 4.5, label = label), colour = "white", size = 10) + coord_polar() + scale_y_continuous(limits = c(0, 5))
}

splitdf <- function(dataframe, seed=NULL) {
  if (!is.null(seed)) set.seed(seed)
  index <- 1:nrow(dataframe)
  trainindex <- sample(index, trunc(length(index)/1.5))
  trainset <- dataframe[trainindex, ]
  testset <- dataframe[-trainindex, ]
  list(trainset=trainset,testset=testset)
}

loadTrans <- function(datefix, aspmode, asptype, maxasp) {
  trans <- openTrans("~/trading/t_eurfix/trans_30.tsv", datefix, aspmode, asptype)
  trans <- trans[,names(trans) %ni% 'endEffect']
  trans <- data.table(trans)
  selected <- trans[,idx[which(S2 >= maxn(S2, maxasp))], by=c('Date')]
  setnames(selected, 'V1', 'idx')
  trans <- merge(selected, trans, by=c('Date', 'idx'))
  as.data.frame(trans)
}

loadTransHist <- function(datefix, aspmode, asptype, maxasp) {
  trans <- loadTrans(datefix, asptype, asptype, maxasp)
  eurusd <- openCommodity("~/trading/EURUSD_day_fxpro_20130611.csv")
  # merge with the currency history
  mergeTrans(trans, eurusd)
}

buildTransOpts <- function() {
  dateFix <- c(0,1)
  maxAspects <- seq(1,10)
  expand.grid(dateFix, aspModes, aspTypes, maxAspects)
}

testGAOptimization <- function() {
  trans.hist <- loadTransHist(0, 'all', 'all', 7)
  trans.training <- subset(trans.hist, Date > as.Date("1999-01-01") & Date < as.Date("2011-01-01"))
  trans.testing <- subset(trans.hist, Date > as.Date("2012-01-01"))
  cols <- c('PT', 'AS', 'PR', 'HR', 'SI', 'LON', 'LAT', 'SP', 'PRLON', 'S', 'S2', 'WD',
            'SU', 'MO', 'ME', 'VE', 'MA', 'JU', 'SA', 'UR', 'NE', 'PL',
            'SUR', 'MOR', 'MER', 'VER', 'MAR', 'JUR', 'SAR', 'URR', 'NER', 'PLR',
            'SULO', 'MOLO', 'MELO', 'VELO', 'MALO', 'JULO', 'SALO', 'URLO', 'NELO', 'PLLO',
            'MOSP', 'MESP', 'VESP', 'MASP', 'JUSP', 'SASP', 'URSP', 'NESP', 'PLSP',
            'MOS', 'MES', 'VES', 'MAS', 'JUS', 'SAS', 'URS', 'NES', 'PLS',
            'MOLA', 'MELA', 'VELA', 'MALA', 'JULA', 'SALA', 'PLLA')

  optimizeRandomForest <- function(string) {
    inc <- which(string == 1)
    selcols <- cols[inc]
    model <- randomForest(Eff ~ ., data = trans.training[,c('Eff',selcols)], importance=TRUE, keep.forest=TRUE, ntree=300)
    err <- median(model$err.rate[,1])
    trans.testing$predicted <- predict(model, newdata=trans.testing[,selcols])
    t1 <- prop.table(table(trans.testing$Eff == trans.testing$predicted))
    tdiff <- as.numeric(round(abs(t1['TRUE']-t1[['FALSE']])*100, digits=2))
    print(tdiff)
    tdiff
  }

  fitnessmax <- function(x) optimizeRandomForest(x)
  fitnessmin <- function(x) -optimizeRandomForest(x)

  # selection
  #gabin_lrSelection - 0.25
  #gabin_nlrSelection
  #gabin_rwSelection - 0.30
  #gabin_tourSelection
  # crossovers
  #gabin_spCrossover(object, parents, ...)
  #gabin_uCrossover(object, parents, ...)
  # mutation
  #gabin_raMutation
  ga("binary", fitness=fitnessmax, nBits=length(cols), names=cols,
     monitor=gaMonitor, maxiter=50, run=10, popSize=100,
     selection=gabin_tourSelection, elitism=0.1)
}

bestRandomForest <- function() {
  threshold=0.65
  trans.hist <- loadTransHist(0, 'all', 'all', 7)
  trans.training <- subset(trans.hist, Date > as.Date("1999-01-01") & Date < as.Date("2009-01-01"))
  trans.testing <- subset(trans.hist, Date > as.Date("2009-01-01") & Date < as.Date("2009-06-01"))
  # start prediction model
  #splits <- splitdf(trans.hist)
  cols <- c("SI", "LON", "SP", "WD", "SU", "ME", "VE", "MA", "JU", "SA",
            "PL", "SULO", "MOLO", "SALO", "URLO", "NELO", "SASP", "PLSP",
            "MOS", "VES", "MAS", "JUS", "SAS", "URS", "NES", "MOLA", "MELA",
            "VELA", "MALA", "JULA")

  #model <- randomForest(Eff ~ ., data = trans.training[,cols], importance=TRUE, keep.forest=TRUE)
  model <- randomForest(Eff ~ ., data = trans.training[,c('Eff',cols)], importance=TRUE, keep.forest=TRUE, ntree=300)
  print(model)
  trans.testing$predicted <- predict(model, newdata=trans.testing[,cols])
  print(prop.table(table(trans.testing$Eff == trans.testing$predicted)))
  print(table(trans.testing$Eff == trans.testing$predicted))
  trans.testing <- data.table(trans.testing)
  setkey(trans.testing, 'Date')
  pred.table <- trans.testing[,as.list(table(predicted)), by=c('Date')]
  pred.table[,prop := (down-up)/(down+up)]
  eurusd <- openCommodity("~/trading/EURUSD_day_fxpro_20130611.csv")
  eurusd <- data.table(eurusd)
  pred.table <- merge(pred.table, eurusd, by='Date')
  pred.table[, predEff := lapply(prop, function(x) ifelse(x > threshold, 'down', ifelse(x < -1*threshold, 'up', NA)))]
  print(table(pred.table$Eff==pred.table$predEff,useNA='always'))
  print(prop.table(table(pred.table$Eff==pred.table$predEff,useNA='always')))
  model
}

predTableCount <- function(pred.table, threshold) {
  pred.table <- data.table(pred.table)
  setkey(pred.table, 'Date')
  pred.table <- pred.table[,as.list(table(predicted)), by=c('Date')]
  pred.table[,prop := (down-up)/(down+up)]
  pred.table[, predEff := lapply(prop, function(x) ifelse(x > threshold, 'down', ifelse(x < -1*threshold, 'up', NA)))]
}

testRandomForest <- function(sinkfile, sigthreshold) {
  if (!hasArg('sinkfile')) stop("Provide a sink filename.")
  sinkfile <- paste("~/trading/predict/", sinkfile, ".txt", sep='')
  sink(npath(sinkfile), append=TRUE)
  transOpts <- buildTransOpts()

  for (n in 1:nrow(transOpts)) {
    datefix <- 0
    aspmode <- as.character(transOpts[[n,2]])
    asptype <- as.character(transOpts[[n,3]])
    maxasp <- transOpts[[n,4]]
    cat("==========================================================================")
    cat("\ntransOpts #", n, " of ", nrow(transOpts), " -  datefix =", datefix, "-  asptype =", aspmode, "-  asptype =", asptype, "-  maxasp =", maxasp, "\n")
    trans.hist <- loadTransHist(datefix, aspmode, asptype, maxasp)

    # start prediction model
    splits <- splitdf(trans.hist)
    trans.training <- splits$trainset
    trans.testing <- splits$testset
    cols <- c('Eff', 'PT', 'SI', 'SP', 'HR',
              "SU", "MO", "ME", "VE", "MA", "JU", "SA", "UR", "NE", "PL",
              #"SUR", "MOR", "MER", "VER", "MAR", "JUR", "SAR", "URR", "NER", "PLR"
              #"SULO", "MOLO", "VELO", "MALO", "JULO", "SALO", "URLO", "NELO", "PLLO",
              "MOSP", "MESP", "VESP", "MASP", "JUSP", "SASP", "URSP", "NESP", "PLSP",
              "MOLA", "MELA", "VELA", "MALA", "JULA", "SALA", "PLLA"
              )

    #model <- randomForest(Eff ~ ., data = trans.training[,cols], importance=TRUE, keep.forest=TRUE)
    model <- randomForest(Eff ~ ., data = trans.training[,cols], importance=TRUE, keep.forest=TRUE, ntree=300)

    #trans.testing$predicted <- predict(model, newdata=trans.testing[,cols])
    #setkey(trans.testing, 'Date')
    #trans.testing[,c('up','down') := as.list(table(Eff)), by=c('idx')]
    #trans.testing[,count := down+up]

    # generate from testing data some random samples and check the prediction results
    terr <- list()
    tdiffs <- list()
    tl1 <- list()
    tl2 <- list()
    samples <- generateSamples(trans.testing, 3)
    for (mysample in samples) {
      predicted <- predict(model, newdata=mysample[,cols])
      t1 <- prop.table(table(mysample$Eff == predicted))
      t2 <- table(mysample$Eff == predicted)
      tdiff <- round(abs(t1['TRUE']-t1[['FALSE']])*100, digits=2)

      if (!is.na(tdiff) & tdiff >= sigthreshold) {
        err.rate <- median(model$err.rate[,1])
        terr[[length(terr)+1]] <- err.rate
        tdiffs[[length(tdiffs)+1]] <- tdiff
        tl1[[length(tl1)+1]] <- t1
        tl2[[length(tl2)+1]] <- t2
      }
    }

    # if the differences are significant in all the test samples
    if (length(tdiffs) == length(samples)) {
      for (i in 1:length(tdiffs)) {
        # print the diffs and the tables
        cat("===================== diff=", tdiffs[[i]], "-  error=", terr[[i]], "\n")
        print(tl1[[i]])
        print(tl2[[i]])
        cat("\n")
      }
      # display the average
      cat("%%%", median(unlist(tdiffs)), "%%%%%%%%%%%%%%%%%%%%\n\n")
    }
    else {
      writeLines("\t\t\tInsignificant")
      cat("\n")
    }


    #varImpPlot(model, type=1, sort=FALSE, n.var=40)
    # remove garbage
    gc()
  }

  sink()
}

generateSamples <- function(ds, n) {
  total <- nrow(ds)
  # build test samples
  samples <- list()
  for (i in 1:n) {
    samples[[i]] <- ds[sample(total, total/2),]
  }
  # finally add the entire data set as a sample
  samples[[length(samples)+1]] <- ds
  samples
}

#dput(as.character(selcols))

gaint_Population <- function (object, ...) {
  min <- object@min
  max <- object@max
  nvars <- length(min)
  population <- matrix(NA, nrow = object@popSize, ncol = nvars)
  for (j in 1:nvars) {
    population[, j] <- sample(min[j]:max[j], object@popSize, replace=TRUE)
  }
  return(population)
}

gaint_raMutation <- function(object, parent) {
  mutate <- parent <- as.vector(object@population[parent, ])
  n <- length(parent)
  j <- sample(1:n, size = 1)
  mutate[j] <- sample(object@min[j]:object@max[j], 1)
  return(mutate)
}

gaint_rwSelection <- function (object, ...) {
  prob <- abs(object@fitness)/sum(abs(object@fitness))
  sel <- sample(1:object@popSize, size = object@popSize, prob = pmin(pmax(0, prob), 1, na.rm = TRUE), replace = TRUE)
  out <- list(population = object@population[sel, , drop = FALSE],
              fitness = object@fitness[sel])
  return(out)
}

processTrans <- function(trans, currency, aspnames, asptypes) {
  currency.train <- subset(currency, Date > as.Date("1998-01-01") & Date < as.Date("2012-01-01"))
  currency.test <- subset(currency, Date > as.Date("2012-01-01"))
  # select only the specified aspects
  trans.cur <- subset(trans, AS %in% aspnames)
  # reset the aspects that are not in the required types
  trans.cur[,planetsList[[1]]] <- t(apply(trans.cur[,c(planetsList[[1]],aspectTypesCols)], 1, removeAspectsOutType, asptype=asptypes))
  # merge with currency data splitting by test & train data
  trans.cur.train <- mergeTrans(trans.cur, currency.train)
  trans.cur.test <- mergeTrans(trans.cur, currency.test)
  list(all=trans.cur, train=trans.cur.train, test=trans.cur.test)
}

processPlanets <- function(planets, currency, sdate, edate) {
  currency <- data.table(currency)
  currency.train <- subset(currency, Date > as.Date(sdate) & Date < as.Date(edate))
  currency.test <- subset(currency, Date > as.Date(edate))
  # merge with currency data splitting by test & train data
  planets.train <- merge(currency.train, planets, by='Date')
  planets.test <- merge(currency.test, planets, by='Date')
  list(all=planets, train=planets.train, test=planets.test)
}

colNLon <- function() {
  c(planetsLonCols)
}

colNLat <- function() {
  c(planetsLatCols)
}

colNSp <- function() {
  c(planetsSpCols)
}

colNLonGrid <- function() {
  c(planetsGridLonCols)
}

colMix1 <- function() {
  c(planetsLonCols, planetsGridLonCols)
}

colMix2 <- function() {
  c(planetsLonCols, planetsGridLonCols, planetsSpCols)
}

colMix3 <- function() {
  c(planetsLonCols, planetsGridLonCols, planetsSpCols)
}

colAll <- function() {
  c(planetsLonCols, planetsSpCols, planetsLatCols, planetsCombLonCols, planetsGridLonCols)
}

testDailyRandomForest <- function(sinkfile, planetsdir, fileno, commoditydir, commodityfile,
                                  sdate, edate, modelfun='randomForest', predproc=FALSE, colNames, chartfile, ...) {
  # Init clock
  ptm <- proc.time()
  if (!hasArg('sinkfile')) stop("Provide a sink filename.")
  sinkfile <- paste("~/trading/predict/", sinkfile, ".txt", sep='')
  sink(npath(sinkfile), append=TRUE)
  # currency data
  currency <- openCommodity(paste("~/trading/", commoditydir, "/", commodityfile, ".csv", sep=''))
  if (hasArg('chartfile')) chart <- fread(paste("~/trading/charts/", chartfile, '.tsv', sep=''), header = T, sep="\t", na.strings="")

  # process planets
  if (exists('chart')) {
    planets <- openPlanets(paste("~/trading/", planetsdir, "/planets_", fileno, ".tsv", sep=''), chart)
  }
  else {
    planets <- openPlanets(paste("~/trading/", planetsdir, "/planets_", fileno, ".tsv", sep=''))
  }

  cat("\n")

  dailyRFFitness <- function(string) {
    looptm <- proc.time()
    # the chromosome that indicate us which columns to include
    inc <- which(string == 1)
    selcols <- colNames[inc]

    cat("---------------------------------------------------------------------------------\n")
    cat("testDailyRandomForestSolution(planetsdir=", shQuote(planetsdir), ", fileno=", fileno, ",\n", sep='')
    cat("\t commoditydir=", shQuote(commoditydir), ", commodityfile=", shQuote(commodityfile), sep='')
    cat(", sdate=", shQuote(sdate), ", edate=", shQuote(edate), ", modelfun=", shQuote(modelfun), sep='')
    cat(", predproc=", predproc, ", chartfile=", shQuote(chartfile), ",\n", sep='')
    cat('\t selcols=c(', paste(shQuote(selcols), collapse=","), "))\n", sep='')

    # process planets
    planets.sp <- processPlanets(planets, currency, sdate, edate)

    # build the samples from testing data
    samples <- generateSamples(planets.sp$test, 3)
    # build model
    modelfun <- get(modelfun)
    model <- modelfun(Eff ~ ., data = planets.sp$train[,c('Eff',selcols), with=FALSE], ...)

    # test the samples
    fitness <- list()
    for (i in 1:length(samples)) {
      predEff <- predict(model, newdata=samples[[i]][,selcols, with=FALSE])
      if (predproc) {
        predEff <- predEffProcessFactor(predEff)
      }
      samples[[i]][, predEff := predEff]
      # day aggregated predictions
      test.result <- testDailyRandomForestPredictions(samples[[i]])
      cat("\t Total = ", test.result$totdays, "/ Trend = ", test.result$tredays, "/ % = ", test.result$percent, "\n")
      fitness[[length(fitness)+1]] <- test.result$tredays
    }

    # fitted value
    evfitness <- fitnessMeanStability(fitness)
    # how long taked to calculate
    cat("\t Predict execution/loop time: ", proc.time()-ptm, " - ", proc.time()-looptm, "\n")
    # output
    cat("### = ", evfitness, "\n")
    # collect garbage
    rm(planets.sp, samples, model)
    gc()
    # return fit
    evfitness
  }

  ga("binary", fitness=dailyRFFitness, names=colNames, nBits=length(colNames),
     monitor=gaMonitor, maxiter=1000, run=50, popSize=500,
     selection=gabin_rwSelection)

  sink()
}

testDailyRandomForestSolution <- function(planetsdir, fileno, commoditydir, commodityfile,
                                          sdate, edate, selcols, modelfun='randomForest', predproc=FALSE, chartfile, ...) {
  # currency data
  currency <- openCommodity(paste("~/trading/", commoditydir, "/", commodityfile, ".csv", sep=''))
  colNames <- c(paste(planetsBaseCols, 'LON', sep=''), paste(planetsBaseCols, 'LAT', sep=''), paste(planetsBaseCols, 'SP', sep=''))
  if (hasArg('chartfile')) chart <- fread(paste("~/trading/charts/", chartfile, '.tsv', sep=''), header = T, sep="\t", na.strings="")

  # process planets
  if (exists('chart')) {
    planets <- openPlanets(paste("~/trading/", planetsdir, "/planets_", fileno, ".tsv", sep=''), chart)
  }
  else {
    planets <- openPlanets(paste("~/trading/", planetsdir, "/planets_", fileno, ".tsv", sep=''))
  }

  # process planets
  planets.sp <- processPlanets(planets, currency, sdate, edate)

  # build the samples from testing data
  samples <- generateSamples(planets.sp$test, 3)
  # build model
  #model <- rpart(as.factor(Eff) ~ ., data = planets.sp$train[,c('Eff',selcols), with=FALSE], method='class')
  modelfun <- get(modelfun)
  model <- modelfun(Eff ~ ., data = planets.sp$train[,c('Eff',selcols), with=FALSE], ...)

  # test the samples
  for (i in 1:length(samples)) {
    predEff <- predict(model, newdata=samples[[i]][,selcols, with=FALSE])
    if (predproc) {
      predEff <- predEffProcessFactor(predEff)
    }
    samples[[i]][, predEff := predEff]
    # day aggregated predictions
    test.result <- testDailyRandomForestPredictions(samples[[i]])
    cat("Total = ", test.result$totdays, "/ Trend = ", test.result$tredays, "/ % = ", test.result$percent, "\n")
  }
  return(model)
}

predEffProcessFactor <- function(predEff) {
  prediffs <- predEff[,1]-predEff[,2]
  ifelse(prediffs >= 0,  'up', 'down')
}

testCorrelationOptimization <- function(sinkfile, directory, fileno) {
  # Init clock
  ptm <- proc.time()
  if (!hasArg('sinkfile')) stop("Provide a sink filename.")
  sinkfile <- paste("~/trading/predict/", sinkfile, ".txt", sep='')
  sink(npath(sinkfile), append=TRUE)
  # correlation methods to test
  corMethods <- c('canberra','euclidian','binary')
  # binarize
  binModes <- c(0,1)
  # remove zero aspects
  zeroaspectsModes <- c(0,1)
  # quitile modes
  qinModes <- c('q1','q2','q3','q4','q5')
  # max aspects modes
  maxaspModes <- c(1,2,3,4,5,6,7)
  # predict Thresholds
  predThresholds <- seq(0.1, 0.9, by=0.1)
  # currency data
  currency <- openCommodity("~/trading/EURUSD_day_fxpro_20130611.csv")
  trans <- openTrans(paste("~/trading/", directory, "/trans_", fileno, ".tsv", sep=''), 1)

  corFitness <- function(x) {
    looptm <- proc.time()
    # build the parameters based on GA indexes
    aspnames <- aspectsCombList[[x[1]]]
    asptypes <- aspectTypesList[[x[2]]]
    cormethod <- as.character(corMethods[[x[3]]])
    binarize <- binModes[[x[4]]]
    rmzeroaspects <- zeroaspectsModes[[x[5]]]
    qinmode <- as.character(qinModes[[x[6]]])
    maxasp <- maxaspModes[[x[7]]]
    kplanets <- planetsCombList[[x[8]]]
    kaspects <- aspectsCombList[[x[9]]]
    predtreshold <- predThresholds[[x[10]]]

    cat("---------------------------------------------------------------------------------\n")
    cat("testCorrelationSolution(directory=", shQuote(directory), ", fileno=", fileno, ",\n", sep='')
    cat('\t aspnames=c(', paste(shQuote(aspnames), collapse=","), "),\n", sep='')
    cat('\t asptypes=c(', paste(shQuote(asptypes), collapse=","), "),\n", sep='')
    cat("\t cormethod=", shQuote(cormethod), ", binarize=", binarize, ", rmzeroaspects=",
        rmzeroaspects, ", qinmode=", shQuote(qinmode), ", maxasp=",
        maxasp, ", predtreshold=", predtreshold, ",\n", sep='')
    cat('\t kplanets=c(', paste(shQuote(kplanets), collapse=","), "),\n", sep='')
    cat('\t kaspects=c(', paste(shQuote(kaspects), collapse=","), "))\n", sep='')

    # process transits
    trans.sp <- processTrans(trans, currency, aspnames, asptypes)
    # build the samples from testing data
    samples <- generateSamples(trans.sp$test, 3)
    # generate the predict table
    predict.table <- predictTransTable(trans.sp$all, trans.sp$train, cormethod, kplanets, kaspects, binarize, rmzeroaspects, qinmode, maxasp)

    # test the samples
    fitness <- list()
    for (i in 1:length(samples)) {
      # day aggregated predictions
      predict.table.aggr <- aggregatePredictTransTable(predict.table, predtreshold)
      test.result <- testAggregatedPredictTransTable(predict.table.aggr, samples[[i]], currency)
      cat("\t Total = ", test.result$totdays, "/ Trend = ", test.result$tredays, "/ % = ", test.result$percent, "\n")
      fitness[[length(fitness)+1]] <- test.result$tredays
    }

    # fitted value
    evfitness <- fitnessMeanStability(fitness)
    # how long taked to calculate
    cat("\t Predict execution/loop time: ", proc.time()-ptm, " - ", proc.time()-looptm, "\n")
    # output
    cat("### = ", evfitness, "\n")
    # collect garbage
    gc()
    # return fit
    evfitness
  }

  minvals <- c(1,1,1,1,1,1,1,1,1,1)
  maxvals <- c(length(aspectsCombList), length(aspectTypesList), length(corMethods),
               length(binModes), length(zeroaspectsModes), length(qinModes),
               length(maxaspModes), length(planetsCombList), length(aspectsCombList), length(predThresholds))
  varnames <- c('aspnames', 'asptypes', 'cormethod', 'binarize', 'rmzeroaspects', 'qinmode', 'maxasp', 'kplanets', 'kaspects', 'predtreshold')

  ga("real-valued", fitness=corFitness, names=varnames,
     monitor=gaMonitor, maxiter=500, run=30, popSize=400, min=minvals, max=maxvals,
     selection=gaint_rwSelection, mutation=gaint_raMutation,
     crossover=gareal_laCrossover, population=gaint_Population)

  sink()
}

testCorrelationSolution <- function(directory, fileno, aspnames, asptypes, cormethod, binarize,
                                    rmzeroaspects, qinmode, maxasp, kplanets, kaspects, predtreshold) {
  # currency data
  currency <- openCommodity("~/trading/EURUSD_day_fxpro_20130611.csv")
  trans <- openTrans(paste("~/trading/", directory, "/trans_", fileno, ".tsv", sep=''), 1)

  # process transits
  trans.sp <- processTrans(trans, currency, aspnames, asptypes)
  # build the samples from testing data
  samples <- generateSamples(trans.sp$test, 5)
  # generate the predict table
  predict.table <- predictTransTable(trans.sp$all, trans.sp$train, cormethod, kplanets, kaspects, binarize, rmzeroaspects, qinmode, maxasp)

  # test the samples
  fitness <- list()
  for (i in 1:length(samples)) {
    # day aggregated predictions
    predict.table.aggr <- aggregatePredictTransTable(predict.table, predtreshold)
    test.result <- testAggregatedPredictTransTable(predict.table.aggr, samples[[i]], currency)
    print(test.result$t1)
    print(test.result$t2)
    cat("\n Total = ", test.result$totdays, "/ Trend = ", test.result$tredays, "/ % = ", test.result$percent, "\n\n")
    fitness[[length(fitness)+1]] <- test.result$tredays
  }

  # fitted value
  cat("\t ### = ", fitnessMeanStability(fitness), "\n\n")
}

fitnessMeanStability <- function(fitness) {
  # last fitness is greater due considers the complete test data we need to
  # adjust dividing by 2 that is the rule used to generate samples.
  fitness[[length(fitness)]] <- fitness[[length(fitness)]]/2
  # penalize the less stable solutions removing a proportional part depending
  # how much are deviated.
  fitness <- unlist(fitness)
  round(mean(fitness) * (1 - sd(fitness) / mean(fitness)))
}

completeEffectList <- function(X) {
  effects <- c('up','down')
  missidx <- effects[effects %ni% names(X)]
  X[missidx] <- 0
  X
}

testDailyRandomForestPredictions <- function(sample.predicted) {
  # less predictions over the number of trading days decay
  totdays <- length(unique(sample.predicted$Date))
  # compare the prediction with the day effect
  testPrediction <- function(x) ifelse(is.na(x[[1]]) | is.na(x[[2]]), NA, x[[1]]==x[[2]])
  sample.predicted[, test := apply(.SD, 1, testPrediction), .SDcols=c('predEff','Eff')]
  # process results
  t1 <- prop.table(table(sample.predicted$test, useNA='always'))
  t2 <- addmargins(table(sample.predicted$test, useNA='always'))
  fitness <- tredays <- percent <- 0
  # only if there are results complete results
  if (all(c('TRUE', 'FALSE', NA) %in% names(t2))) {
    tredays <- abs(as.numeric(t2['TRUE'])-as.numeric(t2['FALSE']))
    percent <- round((tredays/totdays)*100, digits=2)
  }

  list(percent=percent, totdays=totdays, tredays=tredays, t1=t1, t2=t2)
}

testAggregatedPredictTransTable <- function(predict.table.aggr, trans.test, currency) {
  predict.table.aggr <- subset(predict.table.aggr, Date %in% trans.test$Date)
  predict.table.aggr <- merge(predict.table.aggr, currency, by='Date')
  # less predictions over the number of trading days decay
  totdays <- length(unique(trans.test$Date))
  # compare the prediction with the day effect
  testPredictAggr <- function(x) ifelse(is.na(x[[1]]) | is.na(x[[2]]), NA, x[[1]]==x[[2]])
  predict.table.aggr[, test := apply(.SD, 1, testPredictAggr), .SDcols=c('predEff','Eff')]
  # process results
  t1 <- prop.table(table(predict.table.aggr$test, useNA='always'))
  t2 <- addmargins(table(predict.table.aggr$test, useNA='always'))
  fitness <- tredays <- percent <- 0
  # only if there are results complete results
  if (all(c('TRUE', 'FALSE', NA) %in% names(t2))) {
    tredays <- abs(as.numeric(t2['TRUE'])-as.numeric(t2['FALSE']))
    percent <- round((tredays/totdays)*100, digits=2)
  }

  list(percent=percent, totdays=totdays, tredays=tredays, t1=t1, t2=t2)
}

aggregatePredictTransTable <- function(predict.table, threshold) {
  predict.table <- data.table(predict.table)
  setkey(predict.table, 'Date')
  predict.table.aggr <- predict.table[,as.list(completeEffectList(table(corEff))), by=c('Date')]
  predict.table.aggr[,prop := (down-up)/(down+up)]
  # proportion determines a trend that overpass the threshold
  predict.table.aggr[, predEff := lapply(prop, function(x) ifelse(x > threshold, 'down', ifelse(x < -threshold, 'up', NA)))]
}

diffDeg <- function(x, y, orbs) {
  vals <- abs(((x-y+180) %% 360) - 180)
  for (i in 1:length(aspects)) {
    vals[vals >= aspects[i]-orbs[i] & vals <= aspects[i]+orbs[i]] <- aspects[i]
  }
  vals[vals %ni% aspects] <- NA
  return(vals)
}

#ev <- evtree(choice ~ ., data = BBBClub, minbucket = 10, maxdepth = 2)
#rp <- as.party(rpart(choice ~ ., data = BBBClub, minbucket = 10))
#ct <- ctree(choice ~ ., data = BBBClub, minbucket = 10, mincrit = 0.99)
runtest <- function() {
  testDailyRandomForest('output21','dplanets',2,'currency','EURUSD_fxpro','1998','2012','rpart',T,colMix1(),'bceborn')
}

vplayout <- function(x, y) viewport(layout.pos.row = x, layout.pos.col = y)

plotGridAspectsEffect <- function(plotfile, ds, threshold) {
  tdiffs <- list()
  pdf(paste("~/", plotfile, ".pdf", sep=''), width = 11, height = 8, family='Helvetica', pointsize=12)
  for (i in 1:length(planetsGridAspCols)) {
    ##print(ggplot(aes(x=get(selcols[[i]])), data=ds) + facet_grid(Eff ~ .) + geom_density(adjust=1/2) + xlab(selcols[[i]]))
    dsp <- subset(ds, get(planetsGridAspCols[[i]]) == TRUE)
    if (nrow(dsp) > 0) {
      t1 <- prop.table(table(dsp$Eff))
      tdiff <- as.numeric(round(abs(t1['down']-t1[['up']])*100, digits=2))
      if (tdiff >= threshold) {
        tdiffs[[length(tdiffs)+1]] <- tdiff
        p1 <- ggplot(aes_string(x=planetsGridAspCols[[i]], fill="Eff"), data=dsp) + geom_bar(position="fill") + xlab(planetsGridAspCols[[i]]) + scale_y_continuous(breaks=seq(from=0, to=1, by=0.1))
        p2 <- ggplot(aes_string(x=planetsGridAspCols[[i]], fill="Eff"), data=dsp) + geom_bar() + xlab(planetsGridAspCols[[i]])
        grid.newpage()
        pushViewport(viewport(layout = grid.layout(1, 2)))
        print(p1, vp = vplayout(1, 1))
        print(p2, vp = vplayout(1, 2))
      }
    }
  }
  dev.off()
  return(tdiffs)
}

testDailyPlanetsOrbsGA <- function(sinkfile, planetsdir, fileno, commoditydir, commodityfile, sdate, edate, chartfile) {
  # sink output
  if (!hasArg('sinkfile')) stop("Provide a sink filename.")
  sinkfile <- paste("~/trading/predict/", sinkfile, ".txt", sep='')
  sink(npath(sinkfile), append=TRUE)
  # currency data
  currency <- openCommodity(paste("~/trading/", commoditydir, "/", commodityfile, ".csv", sep=''))
  chart <- fread(paste("~/trading/charts/", chartfile, '.tsv', sep=''), sep="\t", na.strings="")
  itest <- 1
  # Init clock
  ptm <- proc.time()

  testDailyPlanetsOrbs <- function(cusorbs) {
    looptm <- proc.time()
    # round orbs to 2 decimals
    cusorbs <- round(cusorbs, digits=2)
    planets <- openPlanets(paste("~/trading/", planetsdir, "/planets_", fileno, ".tsv", sep=''), chart, cusorbs)
    # process planets
    planets.sp <- processPlanets(planets, currency, sdate, edate)
    # process analysis
    fitness <- plotGridAspectsEffect(paste(chartfile, '-', itest), planets.sp$train, 30)

    cat("\n---------------------------------------------------------------------------------\n")
    cat("Test #", itest, "\n", sep='')
    cat('\t cusorbs=c(', paste(cusorbs, collapse=","), ")\n", sep='')
    cat("###", length(fitness), " / %%% =", median(unlist(fitness)), "\n\n")
    # how long taked to calculate
    cat("\t Predict execution/loop time: ", proc.time()-ptm, " - ", proc.time()-looptm, "\n")
    itest <<- itest+1

    # collect garbage
    rm(planets, planets.sp)
    gc()
    return(length(fitness))
  }

  minvals = c(0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
  maxvals = c(4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0)
  varnames = c('0', '30', '45', '60', '72', '90', '120', '135', '144', '150', '180', '18', '40', '52', '80', '104', '108', '155', '160')

  ga("real-valued", fitness=testDailyPlanetsOrbs, names=varnames,
     monitor=gaMonitor, maxiter=50, run=30, popSize=10,
     min=minvals, max=maxvals, selection=gareal_rwSelection)

  sink()
}
