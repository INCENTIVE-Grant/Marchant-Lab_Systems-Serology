#!/usr/bin/env Rscript
##
## Note: Uses UTF-8 encoding to show lower-case "gamma", "ɣ".
##
## Convert the supplied Excel file from a wide-format spread over 3
## worksheets to a single, long-format file, similar to (identical
## to?) that created for the Ruth Aguilar, ISGlobal data set.
##
## IS Global data set header in that CSV file:
##   SubjectID Trial Assay Strain Protein StrainProt Isotype
##   UreaPresent SampleType Value ValueUnit Dilution PlateID Well
##
## Let's revamp the order to something hierarchical:
##   Trial Subject Day Assay Dilution Strain Protein StrainProt IsoType UreaPresent
##   or something like that. Where to place SampleType? Plate & Well at the right end.
##
## VERSION HISTORY
## [2024-12-10 MeD] Initial version
## [2025-01-20 MeD] Revise to tolerate bad matches between Sample Position and Samples.
##                  Just report what has been delivered.
## [2025-03-27 MeD] Update the spelling of some strains:
##   "A/Darwin/09/2021 (H3N2)"                --> "A/Darwin/9/2021 (H3N2)"
##   "A/HongKong/4801/2014 (H3N2)"            --> "A/Hong Kong/4801/2014 (H3N2)"
##   "A/Singapore/IFNIMH-16-0019/2016 (H3N2)" --> "A/Singapore/INFIMH-16-0019/2016 (H3N2)"
##   "A/Guangdong-Moanan/SWL1536/2019 (H1N1)" --> "A/Guangdong-Maonan/SWL1536/2019 (H1N1)"
## [2025-10-27 MeD] Update to use controlled vocabulary
##   ("Controlled-Vocab.R") and adjust output columns to make data
##   integration easier.
##   Change program name from 'parseToCSV.R' --> "parse-Marchand-Sharma_Systems-Serology.R"
## [2026-02-07 MeD] Update to include "ValueUnit" in output data.
##                  Fix items around StrainProt and Protein to match Dobaño dataset.
## [2026-02-23 MeD] Add info to log about translations of names based on Spreadsheet:Notes.
##
##********************************************************************************
library(AnalysisHeader)
library(readxl)
source("Controlled-Vocab.R")

PROGRAM <- 'parse-Marchand-Sharma_Systems-Serology.R'
VERSION <- 'v2.3'
options(warn=1, width=132)

runInfo <- collectRunInfo(program=PROGRAM, version=VERSION)

## Single and Double Horizontal lines for dividing log file output
shLine <- paste(rep('-', 80), collapse='')
dhLine <- paste(rep('=', 80), collapse='')

##--------------------------------------------------------------------------------
## FILE I/O

## Excel file contain 3 data work sheets plus a "Notes" worksheet
inputFile <- 'Marchand-Sharma-Correia_Systems-Serology_2024-10-23.xlsx'
## Worksheet names that contain data
samplesWS   <- 'Database'         # Patient Sample Data
standardsWS <- 'Standard curves'  # Standard Curve Data
positionsWS <- 'Sample position'  # Association between Sample, Assay, and Plate. No well info available.

## Compute output file names
StartTime <- Sys.time()
Today <- format(StartTime, "_%Y%m%d")
outName <- paste0(gsub('\\.xlsx$', '', inputFile), Today, '.csv')
logName <- paste0(gsub('\\.R$', '', PROGRAM), Today, '.log')

## Open the log file and collect all STDOUT & STDERR into the log file
if( !interactive() ) {
    cat("\n*** Redirecting program reporting to Log File:", logName, "\n")
    LogFile <- file(logName, open='wt')
    sink(LogFile)
    sink(LogFile, type='message')
}

print(runInfo)
cat("Controlled Vocabulary:", VocabVersion, "\n")

cat("\nFILENAMES:\n",
    "\tInput: ", inputFile, "\n",
    "\t\tWorksheets:\n",
    "\t\t\tSamples: ", samplesWS, "\n",
    "\t\t\tPositions:", positionsWS, "\n",
    "\t\t\tStandards:", standardsWS, "\n",
    "\tCSV: ", outName, "\n",
    "\tLog: ", logName, "\n\n",
    sep='')

##--------------------------------------------------------------------------------
## LOOKUP TABLES

## Note: Spelling differences between assays names: samples vs standards.
##
## Note: The correct nomenclature is (doi: 10.3389/fimmu.2020.01393):
##       Fc\{gamma}R{Roman Numeral}{A,B}.
##       We will follow the use of Arabic Numerals {2, 3} and upper case.
##       That is: ADCD, ADCP, FcɣR2A, FcɣR2B, FcɣR3A, FcɣR3B
##
## table(samples$Assay)
##
##   ADCD    ADCP FcgR2AH  FcgR2B  FcgR3A  FcgR3B
##    619     311     933     933     933     927
## table(standards$Assay)
##
##  ADCD FcgR2a FcgR2b FcgR3a FcgR3b
##   132    203    198    213    216
##
## table(positions$Assay)
##
##  ADCD FcgR2a FcgR2b FcgR3a FcgR3b
##   546    829    838    882    840

## Proper spelling of assay names for this case (i.e. As specified above which is non-canonical).
## Note that I do use the UTF-8 \gamma character as part of the name.
## The Alias table includes the "correct" name for ADCD and ADCP so lookup and replace is one step.
## FIXME: It may be that the use of \gamma will be a problem. Replace if needed with 'g'.
AssayAlias <- data.frame(Name=  c('ADCD', 'ADCP',
                             'FcɣR2A',  'FcɣR2A', 'FcɣR2B', 'FcɣR2B',
                             'FcɣR3A',  'FcɣR3A', 'FcɣR3B', 'FcɣR3B'),
                         Alias=c('ADCD', 'ADCP',
                             'FcgR2AH', 'FcgR2a', 'FcgR2B', 'FcgR2b',
                             'FcgR3A',  'FcgR3a', 'FcgR3B', 'FcgR3b'),
                          stringsAsFactors=FALSE
                         )

stopifnot(AssayAlias$Name %in% AssayNames)

## Comparison of Short Names for Virus+Protein are fully consistent.
## Need a table to expand them based on the "Notes" worksheet.
## Last 3 rows are controls.
virusProtein <- data.frame(
    Alias=c('A/Darwin/H3N2_HA',
            'B/Austria_HA',
            'A/Wisconsin/H1N1_HA',
            'A/Tasmania/H3N2_HA',
            'B/Washington_HA',
            'B/Phuket_HA',
            'A/Hong Kong/H3N2_HA',
            'A/Guangdong-Maonan/H1N1_HA',
            'B/Washington_HA_Nag',
            'B/Phuket_HA_Nag',
            'A/Hong Kong/H3N2_HA_Nag',
            'A/Brisbane/H1N1_HA',
            'A/Brisbane/H1N1_NA',
            'A/California/H1N1_HA',
            'A/California/H1N1_NA',
            'A/Hong Kong/H3N2_NA',
            'A/Panama/H3N2_HA',
            'A/Singapore/H3N2_HA',
            'gB', 'TT', 'NA'),

    Strain=c('A/Darwin/6/2021 (H3N2)',
             'B/Austria/1359417/2021',
             'A/Wisconsin/588/2019 (H1N1)',
             'A/Tasmania/503/2020 (H3N2)',
             'B/Washington/2/2019',
             'B/Phuket/3073/2013',
             'A/Hong Kong/45/2019 (H3N2)',
             'A/Guangdong-Maonan/SWL1536/2019 (H1N1)',
             'B/Washington/2/2019',         # Duplicate strain; alternative source for HA
             'B/Phuket/3073/2013',          # Duplicate strain; alternative source for HA
             'A/Hong Kong/45/2019 (H3N2)',  # Duplicate strain; alternative source for HA
             'A/Brisbane/2/2018 (H1N1)',
             'A/Brisbane/2/2018 (H1N1)',
             'A/California/4/2009 (H1N1)',
             'A/California/4/2009 (H1N1)',
             'A/Hong Kong/4801/2014 (H3N2)',
             'A/Panama/2007/1999 (H3N2)',
             'A/Singapore/INFIMH-16-0019/2016 (H3N2)',
             NA, NA, NA),

    ## Add the prefix 'p' to 'HA' and 'NA' proteins
    Protein=c("pHA",  "pHA",  "pHA",
              "pHA",  "pHA",  "pHA", "pHA",
              "pHA",  "pHA",  "pHA",
              "pHA",  "pHA",  "pNA",
              "pHA",  "pNA",  "pNA",
              "pHA",  "pHA",
              'CMV glycoprotein B', 'Tetanus toxoid', NA),

    Supplier=c('Native Antigen', 'Native Antigen', 'Ted Ross',
               'Ted Ross', 'Ted Ross', 'Ted Ross', 'Ted Ross',
               'Ted Ross', 'Native Antigen', 'Native Antigen',
               'Native Antigen', 'Ted Ross', 'Ted Ross',
               'Ted Ross', 'Ted Ross', 'Ted Ross',
               'Ted Ross', 'Ted Ross',
               'Ted Ross', 'Ted Ross', NA)
)

stopifnot(virusProtein$Strain[ !is.na(virusProtein$Strain) ] %in% KnownStrains)

cat("\nTranslations used in this code from Spreadsheet names to CSV:\n")

## Display the changes in the names of Assays
tmp <- AssayAlias
colnames(tmp) <- c('CSV-Name', 'Spreadsheet')
inx <- order(tmp[['CSV-Name']])
tmp <- tmp[inx, ]
cat("\nAssay names in Spreadsheet compared with names in CSV file.\n")
print(tmp)

## Display the changes in the names of Proteins.
## See; "Notes" worksheet in spreadsheet
tmp <- virusProtein
inx <- order(tmp$Strain, tmp$Protein, tmp$Supplier)
tmp <- tmp[inx,]
cat("\nProtein short names in Spreadsheet (see 'Notes' in spreadsheet), compared with CSV file.\n")
print(tmp)

##********************************************************************************
##                               SUBROUTINES
##********************************************************************************
#' Utility to output long strings wrapped in a tidy manner
#'
#' I frequently output something similar to:
#'    ~cat("Header:\n\t", paste(vector, collapse=', '), "\n")~
#' which is frequently too long to read easily as the terminal wraps
#' the text. I can improve this by wrapping with `strwrap()` which
#' then requires an additional paste(x, collapse='\n'). This function
#' wraps all that wrapping. (Am I a 'wrap artist'?)
#'
#' @param v Character vector to be concatonated with COMMA and wrapped for output.
#' @param prefix Character to lead each wrapped line with. Default = '\t'
#' @return A long, wrapped character vector of length 1.
wrapText <- function(v, prefix='\t', width=70) {
    return(paste(strwrap(paste(v, collapse=', '), width=width, prefix=prefix, initial=prefix),
                 collapse='\n'))
}

#' Changes a data frame column from character to numeric, while
#' handling common issues
#'
#' Changing a column type from character to numeric seems easy; just
#' use `as.numeric()`.  This, however, throws a number of warnings if
#' the column isn't perfectly formatted for that conversion. Often, a
#' scientist will annotate other aspects of their data within the
#' column, for example, showing missing values as "***" or as the
#' character string, "NA". In addition, data sheets from Europe often
#' include a COMMA rather than a PERIOD as the decimal marker in some
#' subset of the column. This routine detects those cases and converts
#' the "***" and "NA" into NA and the COMMA to a PERIOD. It then
#' applies the `as.numeric()` function, returning the data frame with
#' columns converted.
#'
#' The function writes to STDOUT about the "issues" it has found and
#' how it changed the values.
#'
#' @param dat is a data frame containing the column to convert
#' @param datName is a vector of names of columns to convert
#' @return A data frame matching the input with (a subset of) columns
#'     convert to numeric
convertToNumeric <- function(dat, datName) {
    cat("\nConverting columns in '", datName, "' to numeric.\n", sep='')

    for(i in 1:ncol(dat)) {
        ## Convert the character string, "NA", to a real NA.
        dat[[i]][ ( !is.na(dat[[i]]) ) & (dat[[i]] == "NA") ] <- NA

        ## Convert European Numbers (eg '21516,5') into US Decimal, '21516.5'.
        ## FIXME: doesn't work with monetary COMMAs, eg '1,234.32' or '1.234,32'.
        inxEu <- grepl('^[+-]?[0-9]*,[0-9]*$', dat[[i]])
        if(sum(inxEu) > 0) {
            cat("\tColumn", i, "contains numbers with COMMAs. Convert to PERIOD:\n",
                wrapText(paste0("'", dat[[i]][inxEu], "'"), prefix='\t\t'), "\n")
            dat[[i]][inxEu] <- gsub(',', '.', dat[[i]][inxEu])
        }

        ## Locate lines of STARs - these are used to show NA values
        inxStar <- grepl('^\\*+$', dat[[i]])
        if(sum(inxStar) > 0) {
            cat("\tColumn", i, "contains STARs, '*'. Convert to NA:\n",
                wrapText(paste0("'", dat[[i]][inxStar], "'"), prefix='\t\t'), "\n")
            dat[[i]][inxStar] <- NA
        }

        ## Find all NA and exclude from checking if numeric
        inxNA  <- is.na(dat[[i]])
        inxNum <- grepl('^[+-]?[0-9.]*$', dat[[i]] )
        inxOdd <- !inxNum & !inxNA
        if(sum(inxOdd) > 0) {
            cat("\tColumn", i,"contains non-numeric values. Convert to NA.:\n",
                wrapText(paste0("'", dat[[i]][inxOdd], "'"), prefix='\t\t'), "\n")
            dat[[i]][inxOdd] <- NA
        }
        dat[[i]] <- as.numeric(dat[[i]])
    }
    return(dat)
}

#' Converts the names from the assays from various nicknames to a
#' canonical format
#'
#' The assay names, particularly those associated with the Fcɣ
#' Receptors, have had many spellings on different worksheets. And
#' none of those spellings actually included the GAMMA
#' character. Using a standard lookup table of Alias name and
#' Canonical names, stored in the global variable,
#' \dQuote{AssayAlias}, conversions are performed. Change the table to
#' change or extend the function which otherwise relies on the
#' \code{match()} function.
#'
#' @param nicknames is a vector of assay names of various spellings
#' @return a vector of strings of canonical names. An NA is returned
#'     if a nickname is not recognized; this suggests that one should
#'     extent the \dQuote{AssayAlias} table.
#' @seealso \code{\link{match}}
convertAssayNames <- function(nicknames) {
    inx <- match(nicknames, AssayAlias$Alias)
    stopifnot(all( !is.na(inx) ))   # Plan to always match something
    return(AssayAlias$Name[inx])
}

#' Convert the SampleID (known as \dQuote{ID} on these sheets) to a canonical format
#'
#' Somewhere in the processing of the data, it seems that sample
#' sample IDs have lost part of their name, converting from, for
#' example, \dQuote{ATW003} to a shortened form lacking the leading
#' zeros, \dQuote{ATW3}. This small routine uses regular expressions
#' to separate the alphabetic part of the name from the numeric part,
#' re-adds the leading zeros to the numeric part, and return the
#' re-glued together alpha- plus numeric-part.
#'
#' @param id is a vector of the Subject ID for the INCENTIVE trial.
#' @return a vector of the canonical form of Subject ID,
#'     [A-Z]{3}[0-9]{3}, i.e. three upper-case alphabetic characters
#'     followed by three numeric digits.
cleanupSampleID <- function(id) {
    letr <- casefold(gsub('^([A-Za-z]*)[0-9]*$', '\\1', id), upper=TRUE)
    stopifnot(nchar(letr) == 3)
    numb <- as.integer(gsub('^[A-Za-z]*([0-9]*)$', '\\1', id))
    return(sprintf('%s%03d', letr, numb))
}

#' Convert the visit day (known as \dQuote{Visit} on these sheets) to a canonical format
#'
#' Most of these data report the \dQuote{day} of the visit. Typically,
#' there is the initial visit known as \dQuote{Day Zero}. Additional
#' visits are named by the day of the visit relative to \dQuote{Day
#' Zero}, for example a visit on the third day is \dQuote{Day
#' Three}. These are shortened to \dQuote{D0} and \dQuote{D3}. When
#' the visit occurs at day 28, the name becomes \dQuote{D28} which no
#' longer sorts correctly (D28 < D3).  This routine renames the visit
#' day to include leading zeros so a lexical sort still sorts in the
#' correct order: D000 < D003 < D028. For this trial which includes
#' measurements out to 365 days, we'll use 3 digits.
#'
#' @param day is a vector of the visit day for the INCENTIVE trial.
#' @return a vector of the canonical form of \dQuote{Day} D[0-9]{3},
#'     i.e. the letter 'D' followed by three numeric digits.
cleanupVisitDay <- function(day) {
    letr <- casefold(gsub('^([A-Za-z]*)[0-9]*$', '\\1', day), upper=TRUE)
    stopifnot( letr == 'D' )
    numb <- as.integer(gsub('^[A-Za-z]*([0-9]*)$', '\\1', day))
    return(sprintf('%s%03d', letr, numb))
}

##********************************************************************************
##                                MAIN ROUTINE
##********************************************************************************

cat("\n", dhLine, "\nReading in the Excel Data.\n", sep='')

## Read the Excel data into individual data frames (really, tibbles)
cat("\n\tReading worksheet:", samplesWS, "\n")
samples   <- read_xlsx(path=inputFile, sheet=samplesWS)
N <- ncol(samples)
samples[, 6:N] <- convertToNumeric(samples[, 6:N], "samples")
samples$Assay <- convertAssayNames(samples$Assay)
samples$ID    <- cleanupSampleID(samples$ID)
samples$Visit <- cleanupVisitDay(samples$Visit)

## Read "Sample position" sheet
## Note that "Sample position" merely adds the PlateID to the "Database" sheet.
cat("\n\tReading worksheet:", positionsWS, "\n")
positions <- read_xlsx(path=inputFile, sheet=positionsWS)
for(i in 12:6) positions[[i]] <- NULL   # Remove empty columns
positions$Assay <- convertAssayNames(positions$Assay)
positions$ID    <- cleanupSampleID(positions$ID)
positions$Visit <- cleanupVisitDay(positions$Visit)

cat("\n\tReading worksheet:", standardsWS, "\n")
standards <- read_xlsx(path=inputFile, sheet=standardsWS)
N <- ncol(standards)
standards[, 5:N] <- convertToNumeric(standards[, 5:N], "standards")
standards$Dilution[ (standards$Dilution == '-') ] <- NA
standards$Dilution <- as.numeric(standards$Dilution)
standards$Assay <- convertAssayNames(standards$Assay)

## Re-order just to make some exploration easier
if(1 == 1) {
    inx1 <- order(samples$ID,   samples$Assay,   samples$Visit,   samples$Dilution)
    samples   <- samples[inx1,]

    inx3 <- order(positions$ID, positions$Assay, positions$Visit, positions$Dilution)
    positions <- positions[inx3,]
}

cat(shLine, "\nHead of Excel data worksheets:\n", sep='')

cat("\n\tWorksheet:", samplesWS, "\n")
print(head(samples))

cat("\n\tWorksheet:", positionsWS, "\n")
print(head(positions))

cat("\n\tWorksheet:", standardsWS, "\n")
print(head(standards))

cat(dhLine, "\n")

##--------------------------------------------------------------------------------
## Join the Plate information to the Samples data
##--------------------------------------------------------------------------------
cat("\nJoin Position data onto the Sample data.\n\tIn theory, all we add is the 'Plate' number.\n")

## Create unique (ha!) keys based on the assumed basics: Sample ID, Visit Day, Assay, and Dilution
keySamp <- paste(samples$ID,   samples$Visit,   samples$Assay,   samples$Dilution,   sep='~')
keyPosi <- paste(positions$ID, positions$Visit, positions$Assay, positions$Dilution, sep='~')

## Oh, what a mess!
## > table(samples$Assay)
##   ADCD   ADCP FcɣR2A FcɣR2B FcɣR3A FcɣR3B
##    619    311    933    933    933    927
## > table(positions$Assay)
##   ADCD FcɣR2A FcɣR2B FcɣR3A FcɣR3B
##    546    829    838    882    840
##
## The Assay 'ADCP' is completely missing from 'Positions'.
##
## Start reporting the relationship between 'samples' and 'positions'
cat("\n\t*** WARNING: The assay, 'ADCP', is not present in the Position data set.\n")

## Check for duplicate keys in Samples (worksheet == 'Database').
## Note: current file [2025-01-20] shows no duplicates.
inx <- duplicated(keySamp)
if(sum(inx) > 0) {
    keyDup <- unique(keySamp[inx])      # Which keys are duplicated?
    keyDupList <- strsplit(keyDup, '~') # Prep data frame of duplicated keys in split format
    keyDF <- as.data.frame(t(sapply(keyDupList, function(x) return(x))))
    keyDF$Key <- keyDup                 # Add the key itself to the data frame
    ## Add the rows and the plates that are duplicated to data
    keyDF$DupRows <- sapply(keyDup, function(x) return(paste(which(keySamp == x), collapse=', ')))
    keyDF$DupPlates <- sapply(keyDup,
                              function(x) {
        i <- which(keySamp == x)
        paste(positions$Plate[i], collapse=', ')
    })
    colnames(keyDF) <- c('ID', 'Visit', 'Assay', 'Dilution', 'Key', 'DupRows', 'DupPlates')
    keyDF$Dilution <- as.numeric(keyDF$Dilution)
    inxSort <- order(keyDF$Assay, keyDF$ID, keyDF$Visit, keyDF$Dilution)
    keyDF <- keyDF[inxSort,
                   c('Assay', 'ID', 'Visit', 'Dilution', 'Key', 'DupRows', 'DupPlates')]
    cat("\n*** WARNING: Several Position Keys are duplicated:\n\n")
    print(keyDF)
} else {
    cat("\n*** INFO: There are ZERO Duplicated Sample keys.\n\n")
}

## Check for duplicated Position Keys.
## Note: current file [2025-01-20] shows several. What to do? Just report it.
inx <- duplicated(keyPosi)
if(sum(inx) > 0) {
    keyDup <- unique(keyPosi[inx])
    keyDupList <- strsplit(keyDup, '~')
    keyDF <- as.data.frame(t(sapply(keyDupList, function(x) return(x))))
    keyDF$Key <- keyDup
    keyDF$DupRows <- sapply(keyDup, function(x) return(paste(which(keyPosi == x), collapse=', ')))
    keyDF$DupPlates <- sapply(keyDup,
                              function(x) {
        i <- which(keyPosi == x)
        paste(positions$Plate[i], collapse=', ')
    })
    colnames(keyDF) <- c('ID', 'Visit', 'Assay', 'Dilution', 'Key', 'DupRows', 'DupPlates')
    keyDF$Dilution <- as.numeric(keyDF$Dilution)
    inxSort <- order(keyDF$Assay, keyDF$ID, keyDF$Visit, keyDF$Dilution)
    keyDF <- keyDF[inxSort,
                   c('Assay', 'ID', 'Visit', 'Dilution', 'Key', 'DupRows', 'DupPlates')]
    cat("\n*** WARNING: Several Position Keys are duplicated:\n\n")
    print(keyDF)
} else {
    cat("\n*** INFO: There are ZERO Duplicated Position keys.\n\n")
}

## Which Samples are not in the Position data?
inx <- match(keySamp, keyPosi)
keyDFs <- as.data.frame(samples[ is.na(inx), 1:5])
keyDFs$Key <- keySamp[ is.na(inx) ]
inxSort <- order(keyDFs$Assay, keyDFs$ID, keyDFs$Visit, keyDFs$Dilution)
keyDFs <- keyDFs[inxSort, c('Assay', 'ID', 'Visit', 'Dilution', 'Key')]
rownames(keyDFs) <- 1:nrow(keyDFs)

cat("\n", shLine, "\n",
    "\t*** WARNING: There are several Samples without corresponding Positions:\n\n")
print(keyDFs)
cat("\nThese samples will have an NA for their Plate entry\n\n")

## Create an index to connect between Samples and Positions. Pull in the Plate No. when possible.
cat(shLine, "\nAssigning Plate to Samples.\n\n")
inx <- match(keySamp, keyPosi)
samples$Plate <- NA_character_
samples$Plate[ !is.na(inx) ] <- as.character(positions$Plate[ inx[ !is.na(inx) ]])

## Attempt to combine 'keyDF' with duplicated keys into Samples
inx <- match(keySamp, keyDF$Key)
samples$Plate[ !is.na(inx) ] <- keyDF$DupPlate[ inx[!is.na(inx)] ]

cat("\nDistribution of Samples across Plates:\n")
print(table(samples$Plate))

cat(dhLine,"\n")

##********************************************************************************
## Prepare to output the combined "samples" and "standards".
## Columns:
##   SampleType Trial Subject Day Assay Dilution Strain Protein
##   StrainProt IsoType UreaPresent or something like that.  Plate &
##   Well at the right side.
## Values for SampleType are: Blank, PosCtrl, NegCtrl, Samp
##
## From 'samples', repeat columns: Assay, QIV, ID, Visit, Dilution, Plate
##                 Values in strains: A/Darwin/... up to TT
##
## Conversion of Column names
##    output: "longTab"    input: "samples"     input: "standards"
##        SampleType              --                 ID
##        Trial                   QIV                --
##        Subject                 ID                 --
##        Day                     Visit              --
##        Assay                   Assay              Assay
##        Strain                  col 6-25           col 5-24
##        Protein                   "                  "
##        StrainProt                "                  "
##        Dilution                Dilution           Dilution
##        Value                     "                  "
##        Plate                    Plate              Plate
##
## How big is the output array?
## dim(samples) == c(4656, 26)
## How many fixed columns:
##    SampleType, Trial, Subject, Day, Assay, Strain, Prot, StrainProt, Dilution, Plate == 10
## How many Value columns? 6:25 == 20.

## Re-format names to a standard format for all data sets
trial <- ifelse(samples$QIV == 1, 'QIV1',
         ifelse(samples$QIV == 2, 'QIV2',
         ifelse(samples$QIV == 3, 'QIV3', NA)))
## Convert shortname of virus-strain_protein into two columns: WHO Strain and Protein
inx <- match(colnames(samples), virusProtein$Alias)
analyteCols <- which( !is.na(inx) )
strain  <- virusProtein$Strain[ inx[ !is.na(inx) ] ]
protein <- virusProtein$Protein[ inx[ !is.na(inx) ] ]
pSource <- virusProtein$Supplier[ inx[ !is.na(inx) ] ]
strainProt <- colnames(samples)[ !is.na(inx) ]

## So, the output matrix is: 4656 * 20 rows with 13 columns.
nRowInp <- nrow(samples)
colNames <- c('SampleType', 'Trial', 'SubjectID', 'Day', 'Assay', 'Strain', 'Prot', 'StrainProt',
              'Dilution', 'Value', 'ValueUnit', 'Plate', 'Well')
nColOut <- length(colNames)
numAnalytes <- length(strain)
nRowOut <- numAnalytes * nRowInp

## Document for the logs
cat("Collecting 'samples' information. Expected Rows =", nRowOut,
    ", expected Columns =", nColOut, ".\n\n")

## Prepare the output data frame
outMat <- data.frame(SampleType = rep('Samp', times=nRowOut),
                     Trial=rep(trial, times=numAnalytes),
                     SubjectID=rep(samples$ID, times=numAnalytes),
                     Day=rep(samples$Visit, times=numAnalytes),
                     Assay=rep(samples$Assay, times=numAnalytes),
                     Strain=rep(strain, each=nRowInp),
                     Protein=rep(protein, each=nRowInp),
                     StrainProt=rep(strainProt, each=nRowInp),
                     Dilution=rep(samples$Dilution, times=numAnalytes),
                     Value=NA_real_,
                     ValueUnit='MFI',
                     Supplier=rep(pSource, each=nRowInp),
                     Plate=rep(samples$Plate, times=numAnalytes),
                     Well=NA_character_,
                     stringsAsFactors=FALSE
                     )

## Loop over result value and jam them into the outMat in the correct location
cat("Mapping 'samples' values into long output:\n")
N <- nRowInp
for(i in seq_along(analyteCols)) {
    col <- analyteCols[i]
    d <- c(samples[, col])[[1]]
    lo <- ((i - 1) * N) + 1
    hi <- i * N
    cat(sprintf('\t[%d,%d] Part %d - %s (%d rows)', lo, hi, i, colnames(samples)[col], N), "\n")
    outMat$Value[lo:hi] <- d
}

## Order things to make cross-checking easier
ind <- order(outMat$Trial, outMat$SubjectID, outMat$Day,
             outMat$Assay, outMat$StrainProt, outMat$Dilution)
outMat <- outMat[ind, ]

## Document what was made for the logs
cat(shLine, "\nOutput data set of samples is ", nrow(outMat),
    " rows by ", ncol(outMat), " columns.\n", sep='')
cat("\nExample of long sample data:\n")
print(head(outMat, 30), row.names=FALSE)

cat(dhLine, "\n")

##********************************************************************************
## Now repeat for the "standards".
##
## <copy from above>
## Conversion of Column names
##    output: "longTab"    input: "samples"     input: "standards"
##        SampleType              --                 ID
##        Trial                   QIV                --
##        Subject                 ID                 --
##        Day                     Visit              --
##        Assay                   Assay              Assay
##        Strain                  col 6-25           col 5-24
##        Protein                   "                  "
##        StrainProt                "                  "
##        Dilution                Dilution           Dilution
##        Value                     "                  "
##        Plate                    Plate              Plate
##        Well                     NA                 NA
##
## How big is the output array?
## dim(standards) == c(962, 24)
## How many fixed columns on output:
##    SampleType, Trial, Subject, Day, Assay, Strain, Prot, StrainProt, Dilution, Plate, Well (=11)
##
## How many Value columns? 5:24 == 20.
## Total == 962 * 20 = 19240 rows

## Convert shortname of virus-strain_protein into two columns: WHO Strain and Protein
inx <- match(colnames(standards), virusProtein$Alias)
analyteCols <- which( !is.na(inx) )
strain  <- virusProtein$Strain[ inx[ !is.na(inx) ] ]
protein <- virusProtein$Protein[ inx[ !is.na(inx) ] ]
pSource <- virusProtein$Supplier[ inx[ !is.na(inx) ] ]
strainProt <- colnames(standards)[ !is.na(inx) ]

## Derive a standardized SampleType from the ID
sampleType <- ifelse(standards$ID == 'Blank', 'Blank',
              ifelse(standards$ID == 'Multigam', 'Stnd',
              ifelse(standards$ID == 'Pool 1', 'PosCtrl',
              ifelse(standards$ID == 'Pool 2', 'PosCtrl', NA))))

## So, the output matrix is: 4656 * 20 rows with 10 + 1 columns.
nRowInp <- nrow(standards)
colNames <- c('SampleType', 'Trial', 'SubjectID', 'Day', 'Assay', 'Strain', 'Prot', 'StrainProt',
              'Dilution', 'Value', 'Plate', 'Well')
nColOut <- length(colNames)
numAnalytes <- length(strain)
nRowOut <- numAnalytes * nRowInp

## Document for the logs
cat("Collecting 'standards' information. Expected Rows =", nRowOut,
    ", expected Columns =", nColOut, ".\n\n")

## Build the output data frame
outStd <- data.frame(SampleType=rep(sampleType, times=numAnalytes),
                     Trial=NA_character_,
                     SubjectID=rep(standards$ID, times=numAnalytes),
                     Day=NA_character_,
                     Assay=rep(standards$Assay, times=numAnalytes),
                     Strain=rep(strain, each=nRowInp),
                     Protein=rep(protein, each=nRowInp),
                     StrainProt=rep(strainProt, each=nRowInp),
                     Dilution=rep(standards$Dilution, times=numAnalytes),
                     Value=NA_real_,
                     ValueUnit='MFI',
                     Supplier=rep(pSource, each=nRowInp),
                     Plate=as.character(rep(standards$Plate, times=numAnalytes)),
                     Well=NA_character_ ,
                     stringsAsFactors=FALSE
                     )

## Loop over result value and jam them into the outStd in the correct location
cat("Mapping 'standards' values into long output:\n")
N <- nRowInp
for(i in seq_along(analyteCols)) {
    col <- analyteCols[i]
    d <- c(standards[, col])[[1]]
    lo <- ((i - 1) * N) + 1
    hi <- i * N
    cat(sprintf('\t[%d,%d] Part %d - %s (%d rows)', lo, hi, i, colnames(standards)[col], N), "\n")
    outStd$Value[lo:hi] <- d
}

## Write some material to the logs to show that standards are collected.
cat(shLine, "\nOutput data set of 'standards' is ", nrow(outStd),
    " rows by ", ncol(outStd), " columns.\n", sep='')

## Set up indexes to select a small amount of Standards data
inxBlk <- outStd$SampleType == 'Blank' & outStd$SubjectID == 'Blank' &
    outStd$StrainProt == 'A/Darwin/H3N2_HA' & outStd$Plate %in% c(1,2)
inxPCtrl <- outStd$SampleType == 'PosCtrl' & outStd$SubjectID == 'Pool 1' &
    outStd$StrainProt == 'A/Darwin/H3N2_HA' & outStd$Plate %in% c(1,2)
inxStd <- outStd$SampleType == 'Stnd' & outStd$SubjectID == 'Multigam' &
    outStd$StrainProt == 'A/Darwin/H3N2_HA' & outStd$Plate %in% c(1,2) &
    outStd$Assay == 'FcɣR2B'

cat("\nExample BLANK standards:\n")
print(outStd[inxBlk,])

cat("\nExample Positive CONTROL standards:\n")
print(outStd[inxPCtrl,])

cat("\nExample STANDARD CURVE standards:\n")
print(outStd[inxStd,])

cat(dhLine, "\n")

##********************************************************************************
## Do the output

## Prepare the output material
stopifnot( colnames(outMat) == colnames(outStd),
          sapply(outMat, function(x) class(x)) == sapply(outStd, function(x) class(x))
          )

## Combine the two output data sets: samples and standards, into one data frame.
cat("Prepare the output data frame from 'samples' and 'standards':\n")
joint <- rbind(outMat, outStd)

##--------------------------------------------------------------------------------
## PATCH the column 'StrainProt' to standard format.
## First confirm correct Strain & Protein
cat(shLine, "\n")
cat("\nPatch 'StrainProt' column names to match Dobaño dataset naming.\n")
inx <- match(joint$StrainProt, virusProtein$Alias)
stopifnot(all(virusProtein$Strain[inx] == joint$Strain, na.rm=TRUE),
          all(virusProtein$Protein[inx] == joint$Protein, na.rm=TRUE),
          !is.na(joint$Protein)
          )
## When the controls, TT and gB, are used, there is an NA for Strain. Skip them.
inx <- !is.na(joint$Strain)
newStrainProt <- paste0(joint$Protein[inx], '_',
                        gsub('^([AB]/[A-Za-z ]*)[/-].*$', '\\1', joint$Strain[inx]))

## Log the changes to StrainProt
cat("\nChanges made to StrainProt are (Controls, gB, TT, are skipped):\n")
print(unique(data.frame(Strain=joint$Strain[inx],
                        Protein=joint$Protein[inx],
                        OldStrainProt=joint$StrainProt[inx],
                        NewStrainProt=newStrainProt)))
## Make the actual change to StrainProt
joint$StrainProt[inx] <- newStrainProt

##--------------------------------------------------------------------------------
## Output the data frame and exit
cat("\nOutput whole data set to:\n\t", outName, ".\n", sep='')
cat("\tFinal size is: ", nrow(joint), " rows by ", ncol(joint), " columns.\n\n", sep='')
write.csv(joint, file=outName, row.names=FALSE)

cat(dhLine, "\n")

##********************************************************************************
## Close up
DoneTime <- Sys.time()
if( !interactive() ) {
    cat("Completed:", format(DoneTime, "%Y-%m-%d %H:%M:%S"), "\n")
    cat("Elapsed time:", difftime(DoneTime, StartTime, units='secs'), "secs.\n")

    ## Close up the log file (file = NULL)
    sink(type='message')
    sink()
    close(LogFile)
}

cat("Completed:", format(DoneTime, '%Y-%m-%d %H:%M:%S'), "\n")

##********************************************************************************
## End Of File
