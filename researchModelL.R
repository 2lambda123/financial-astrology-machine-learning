# Title,  : Daily aspects ModelL energy research.
# Objective : Research model generalizing the aspects per former planet.
# Created by: pablocc
# Created on: 24/09/2020

library(caret)
library(magrittr)
library(parallel)
library(psych)
library(plyr)
library(randomForest)
library(rattle)
library(tidyverse)
source("./indicatorPlots.r")

dailyAspects <- prepareHourlyAspectsModelK()
symbol <- "LINK-USD"
securityData <- mainOpenSecurity(
  symbol, 14, 28, "%Y-%m-%d",
  "2010-01-01", "2020-08-31"
)

# Experiment with Random Forest model.
aspectViewRaw <- dailyAspects[p.x == "VE" & aspect == 60,]
#aspectViewRaw <- dailyAspects[p.x != "MO"]
aspectsT <- paste("a", aspects, sep = "")
aspectsX <- paste("a", aspects, ".x", sep = "")
aspectsY <- paste("a", aspects, ".y", sep = "")
aspectsG <- paste("a", aspects, ".g", sep = "")
aspectsCols <- c(
  aspectsX, aspectsY, aspectsT,
  "sp.y", "sp.x", "dc.y", "dc.x", "spd", "spp", "acx", "acy", "agt",
  "ME.x", "VE.x", "SU.x", "MA.x", "JU.x", "NN.x", "SA.x", "UR.x",
  "NE", "PL", "MO", "ME", "VE", "SU", "MA", "JU", "SA",
  "ME.y", "VE.y", "SU.y", "MA.y", "JU.y", "NN.y", "SA.y", "UR.y",
  "wd", "zx", "zy"
)

selectCols <- c("Date", aspectsCols)
aspectView <- aspectViewRaw[, ..selectCols]
aspectView <- merge(securityData[, c('Date', 'diffPercent')], aspectView, by = "Date")

varCorrelations <- aspectView[, -c('Date')] %>%
  cor() %>%
  round(digits = 2)
finalCorrelations <- sort(varCorrelations[, 1])
print(finalCorrelations)

# The effect polarity of an aspects seems to depend on the 150 angle that is neutral
# and apply differently depending on other active aspect polarities when JU and MA
# form part of that interactions.
effectLinearModel <- lm(
  diffPercent ~ MO +
    JU.y +
    MA.y +
    a135.y +
    a150.y +
    a180.y +
    a45.x +
    a60.x +
    a150.x +
    a90.y,
  data = aspectView
) %>% summary()
