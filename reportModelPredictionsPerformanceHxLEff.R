# Title     : Models predictions accuracy performance / stability CSV report.
rm(list = ls())
library(caret)
library(psych)
source("analysis.r")

testPredictAccuracy <- function(predictFilename) {
  cat("Processing: ", predictFilename, "\n")
  filenameParts <- unlist(strsplit(predictFilename, "-"))
  symbolTest <- paste(filenameParts[1], filenameParts[2], sep = "-")
  startDate <- as.Date(format(Sys.Date() - 210, "%Y-%m-01"))
  securityDataTest <- mainOpenSecurity(
    symbolTest, 2, 4,
    "%Y-%m-%d", startDate
  )

  predictPath <- paste(basePath, predictFilename, sep = "")
  predictFileInfo <- file.info(predictPath)
  dailyIndicator <- fread(predictPath)

  dailyIndicator[, Date := as.Date(Date)]
  dailyIndicator[, YearMonth := format(Date, "%Y-%m")]
  dailyIndicator <- merge(
    securityDataTest[, c('Date', 'Mid', 'diffPercent', 'Eff', 'HxLEff')],
    dailyIndicator,
    by = "Date"
  )

  calculateAccuracy <- function(monthlyData) {
    categoryLevels = c("buy", "sell")
    confusionData <- table(
      actualclass = factor(monthlyData$HxLEff, levels = categoryLevels),
      predictedclass = factor(monthlyData$EffPred, levels = categoryLevels)
    ) %>% caret::confusionMatrix()

    accuracy <- confusionData$overall['Accuracy']
    prevalence <- confusionData$byClass['Prevalence']

    list(
      N = nrow(monthlyData),
      Accuracy = accuracy,
      Prevalence = prevalence
    )
  }

  accuracyTest <- dailyIndicator[, calculateAccuracy(.SD), by = "YearMonth"]
  # Filter months that don't have at least N observations yet.
  accuracyTest <- accuracyTest[N >= 7]

  # Calculate descriptive statistics for Accuracy / Prevalence.
  descriptives6m <- round(describe(head(accuracyTest[, c('Accuracy', 'Prevalence')], 6)), 3)
  descriptives3m <- round(describe(tail(accuracyTest[, c('Accuracy', 'Prevalence')], 3)), 3)
  descriptives2m <- round(describe(tail(accuracyTest[, c('Accuracy', 'Prevalence')], 2)), 3)
  descriptives1m <- round(describe(tail(accuracyTest[, c('Accuracy', 'Prevalence')], 1)), 3)
  createDate <- predictFileInfo$mtime
  prodDays <- as.numeric(difftime(Sys.Date(), as.Date(createDate), units = "days"))

  return(
    data.table(
      PredictFile = predictFilename,
      Created = createDate,
      ProdDays = prodDays,
      Acc6m = descriptives6m$mean[1],
      Acc3m = descriptives3m$mean[1],
      Acc2m = descriptives2m$mean[1],
      Acc1m = descriptives1m$mean[1],
      AccSD6m = descriptives6m$sd[1],
      AccSD3m = descriptives3m$sd[1],
      AccSD2m = descriptives2m$sd[1],
      Prev6m = descriptives6m$mean[2],
      Prev3m = descriptives3m$mean[2],
      Prev2m = descriptives2m$mean[2],
      Prev1m = descriptives1m$mean[2],
      PrevSD6m = descriptives6m$sd[2],
      PrevSD3m = descriptives3m$sd[2],
      PrevSD2m = descriptives2m$sd[2]
    )
  )
}

getMySymbolsData("working")

#basePath <- "~/Sites/own/trading-signal-processing/csv_indicators/"
#basePath <- "./predictions/"
basePath <- "./predictions/"
predictFiles <- list.files(basePath, pattern = "*.csv")
testResults <- setDT(rbindlist(lapply(predictFiles, testPredictAccuracy)))
reportDate <- format(Sys.Date(), "%Y-%m-%d")
modelsPredictSummaryFilename <- paste("./predictions/", "models-predict-performance-hleff-", reportDate, ".csv", sep = "")

fwrite(testResults, modelsPredictSummaryFilename)
cat("Models summary exported to:", modelsPredictSummaryFilename, "\n")