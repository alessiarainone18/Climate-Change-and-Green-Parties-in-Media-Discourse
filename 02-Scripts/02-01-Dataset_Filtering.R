# Load packages
library(tidyverse)
library(quanteda)
library (openxlsx)

# Set up WD
setwd("/Users/alessiarainone/Desktop/Data-Mining-Project_Climate-Change-Media-Attention/01-Data")

# Load data
data <- read.delim("dataset_climate.tsv", sep = "\t", encoding = "UTF-8")
data <- data %>% mutate(year = year(as_datetime(pubtime)))

# Filter German articles since there are to few french in the database
data_de <- data %>% filter(language == "de")
grouped_by_medium_de <- data_de %>% group_by(year, medium_code) %>% summarize(n = n())
grouped_by_year_de <- data_de %>% group_by(year) %>% summarize(n = n())

# Define keywords to detect green parties
party_keywords <- c("Grüne", "GPS", "Junge Grüne Schweiz", "Grünliberale Partei", "GLP")

data_de$content <- as.character(data_de$content)
filtered_data <- data_de %>% 
  filter(grepl(paste(party_keywords, collapse = "|"), content, ignore.case = TRUE)) %>%
  mutate(wordcount = str_count(content, "\\S+")) %>%
  distinct(medium_code, content, .keep_all = TRUE) %>%
  filter(wordcount >= 200 & wordcount <= 2000, year >= 2014)

### ML APPROACH ---- 
testsample_data <- sample_n(filtered_data, 500)
write.xlsx(testsample_data, file="testsample_data.xlsx", overwrite = TRUE, asTable = TRUE)

# Handcoding done in Excel
sample_coded <- read.xlsx("coded_testsample.xlsx", sheet="coded data")         
sample_coded$relevance=as.factor(sample_coded$relevance)

# Training set
set.seed(123)  
train_indices <- sample(nrow(sample_coded), 400)
train <- sample_coded[train_indices, ]
train$text <- train$content
test <- sample_coded[-train_indices, ]  
test$text <- test$content

myCorpusTrain <- corpus(train)

tok2 <- tokens(myCorpusTrain , remove_punct = TRUE, remove_numbers=TRUE, 
               remove_symbols = TRUE, 
               split_hyphens = TRUE, remove_separators = TRUE, remove_url=TRUE)
tok2 <- tokens_remove(tok2, stopwords("de"))

# remove the unicode symbols
tok2 <- tokens_remove(tok2, c("0*"))
tok2 <- tokens_wordstem (tok2)
Dfm_train <- dfm(tok2)

# Let's trim the dfm in order to keep only tokens that appear in 2 or more tweets (tweets are short texts!)
# and let's keep only features with at least 2 characters
Dfm_train <- dfm_trim(Dfm_train , min_docfreq = 2, verbose=TRUE)
Dfm_train  <- dfm_remove(Dfm_train , min_nchar = 2)
topfeatures(Dfm_train , 20)  # 20 top words

# TEST SET
myCorpusTest <- corpus(test)
tok <- tokens(myCorpusTest , remove_punct = TRUE, remove_numbers=TRUE, 
              remove_symbols = TRUE, 
              split_hyphens = TRUE, remove_separators = TRUE, remove_url=TRUE)
tok <- tokens_remove(tok, stopwords("de"))
tok <- tokens_remove(tok, c("0*"))
tok <- tokens_wordstem (tok)
Dfm_test <- dfm(tok)
Dfm_test<- dfm_trim(Dfm_test, min_docfreq = 2, verbose=TRUE)
Dfm_test<- dfm_remove(Dfm_test, min_nchar = 2)
topfeatures(Dfm_test , 20)  # 20 top words

setequal(featnames(Dfm_train), featnames(Dfm_test)) 
nfeat(Dfm_test)
nfeat(Dfm_train)
test_dfm  <- dfm_match(Dfm_test, features = featnames(Dfm_train))
nfeat(test_dfm)
setequal(featnames(Dfm_train), featnames(test_dfm))

train <- as(Dfm_train, "dgCMatrix") 
test <- as(test_dfm, "dgCMatrix") 

# Machine Learning Model to categorize relevance ---- 
# Bernoulli Naive Bayes model
system.time({
  NB <- bernoulli_naive_bayes(x = train, y = Dfm_train@docvars$relevance)
})

# Make predictions on the test set
predicted_nb <- predict(NB, test)

# Check prior probabilities
priors <- prop.table(table(Dfm_train@docvars$relevance))
print(priors)

# Generate the confusion matrix
conf_matrix <- table(Predicted = predicted_nb, Actual = Dfm_test@docvars$relevance)
print(conf_matrix) ## 


### Use on whole data---- 
# Preprocess your whole dataset (assuming 'myCorpusWholeData' is your full corpus)
filtered_data$text <- filtered_data$content
myCorpusWholeData <- corpus(filtered_data)  # Replace with your actual data
tok_whole <- tokens(myCorpusWholeData, remove_punct = TRUE, remove_numbers = TRUE, 
                    remove_symbols = TRUE, split_hyphens = TRUE, 
                    remove_separators = TRUE, remove_url = TRUE)
tok_whole <- tokens_remove(tok_whole, stopwords("en"))
tok_whole <- tokens_wordstem(tok_whole)

# Create the DFM for the whole data
Dfm_whole <- dfm(tok_whole)

# Trim and remove low-frequency words, similar to the training data
Dfm_whole <- dfm_trim(Dfm_whole, min_docfreq = 2, verbose = TRUE)
Dfm_whole <- dfm_remove(Dfm_whole, min_nchar = 2)

# Ensure that features in the whole data match with the training data
Dfm_whole_matched <- dfm_match(Dfm_whole, features = featnames(Dfm_train))
whole_data <- as(Dfm_whole_matched, "dgCMatrix")

# Use the trained model to predict the relevance of the whole dataset
predicted_whole_data <- predict(NB, whole_data)

# Save predictions in a new column in your original dataset (if desired)
filtered_data$predicted_relevance <- predicted_whole_data

## See how many articles are seen as relevant
filtered_data %>%
  count(predicted_relevance)

# Still 9291 articles (too many)

# Exclude local politics
local_terms <- c("Gemeinderat", "Stadtrat", "Ortsparlament", "Quartierverein",
                 "Gemeindeversammlung", "Baukommission", "Ortsplanung")
filtered_national <- filtered_data %>% filter(!grepl(paste(local_terms, collapse = "|"), content, ignore.case = TRUE))

# Filter general on polictis and Switzerland
general_terms <- c("Partei", "politisch", "Politik", "Parlament", "Gesetz", "Bundesrat")
swiss_terms <- c("Schweiz", "Schweizer", "eidgenössisch", "national", "kantonal", "Regierungsrat", "Grossrat", "Kantonsrat")

filtered_swiss <- filtered_national %>%
  filter(grepl(paste(general_terms, collapse = "|"), content, ignore.case = TRUE)) %>%
  filter(grepl(paste(swiss_terms, collapse = "|"), content, ignore.case = TRUE)) %>%
  filter(rubric != "international", medium_code != "BAZ", medium_code != "NNBE")

filtered_swiss %>%
  count(predicted_relevance)

# Check on random sample
check_sample <- sample_n(filtered_swiss, 100)
check_sample %>%
  count(predicted_relevance)

table_result <- table(check_sample$head, check_sample$predicted_relevance)
table_result


# Plot Swiss reports per year and medium
grouped_by_medium_swiss <- filtered_swiss %>% group_by(year, medium_code) %>% summarize(n = n())
medium_labels_swiss <- medium_labels[c("ZWAO", "NZZO", "NNTA", "SRF", "BLIO")]

ggplot(grouped_by_medium_swiss, aes(x = year, y = n, color = medium_code, group = medium_code)) +
  geom_line() +
  labs(title = "Climate Change Reports in Swiss Politics", x = "Year", y = "Number of Records") +
  scale_x_continuous(breaks = 2014:2024) +
  scale_color_manual(values = medium_colors, labels = medium_labels_swiss) +
  theme_minimal()

cat("Number of filtered articles:", nrow(filtered_swiss), "\n")
print(filtered_swiss %>% summarise(wordcount_mean = mean(wordcount)))

# Tokenization and stopword removal, as lots of unnecessary tokens
# which will make analysis by API more expensive
myCorpus <- corpus(filtered_swiss$content)
strwrap(as.character(myCorpus)[1])

tok_clean <- tokens(myCorpus, 
                    remove_punct = TRUE, remove_numbers = TRUE, 
                    remove_symbols = TRUE, split_hyphens = TRUE, 
                    remove_separators = TRUE) %>%
  tokens_remove(stopwords("german")) 

word_counts <- sapply(tok_clean, function(x) str_count(paste(x, collapse = " "), "\\S+"))
mean_tok <- mean(word_counts, na.rm = TRUE)
mean_tok 

## TOTAL OF TOKENS: 3'400'000
## TOTAL OF TOKENS AFTER ML APPROACH: 2'616'600