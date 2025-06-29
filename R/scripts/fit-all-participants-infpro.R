rm(list = ls())

library(tidyverse)
library(cmdstanr)
library(rutils)
library(ggrepel)
library(grid)
library(gridExtra)
library(furrr)
library(loo)

utils_loc <- c("R/utils/plotting-utils.R", "R/utils/utils.R")
walk(utils_loc, source)

if (!dir.exists("data/")) dir.create("data/")
if (!dir.exists("data/infpro_task-cat_beh/")) dir.create("data/infpro_task-cat_beh/")
if (!dir.exists("data/infpro_task-cat_beh/models/")) dir.create("data/infpro_task-cat_beh/models/")
if (!dir.exists("data/infpro_task-cat_beh/model-plots/")) dir.create("data/infpro_task-cat_beh/model-plots/")
if (!dir.exists("data/infpro_task-cat_beh/figures/")) dir.create("data/infpro_task-cat_beh/figures/")


# Fit Models or Load Saved Results? ---------------------------------------

is_saved <- c(TRUE, FALSE)[1]


# Load Data and Preprocess Them -------------------------------------------


file_loc_train <- "data/infpro_task-cat_beh/infpro_task-cat_beh.csv"
file_loc_transfer <- "data/infpro_task-cat_beh/infpro_task-cat2_beh.csv"
# tbl_train <- read_csv(file_loc_train, show_col_types = FALSE)
# tbl_transfer <- read_csv(file_loc_transfer, show_col_types = FALSE)
tbl_train <- read_csv(file_loc_train)
tbl_transfer <- read_csv(file_loc_transfer)
colnames(tbl_transfer) <- str_replace(colnames(tbl_transfer), "cat2", "cat")
tbl_train$session <- "train"
tbl_transfer$session <- "transfer"

# re-coding category and response due to ordering constraints in the Bayesian models
tbl_both <- tbl_train  %>% 
  rbind(tbl_transfer) %>%
  mutate(
    d1i_z = scale(d1i)[, 1],
    d2i_z = scale(d2i)[, 1],
    category = recode_factor(category, "B" = "C", "C" = "B"),
    response = recode_factor(response, "B" = "C", "C" = "B"),
    category_int = as.numeric(factor(category, levels = c("A", "B", "C"), ordered = TRUE)),
    response_int = as.numeric(factor(response, levels = c("A", "B", "C"), ordered = TRUE)),
  )

# keep these summary stats for plotting results in untransformed space
mean_d1i <- mean(tbl_both$d1i)
sd_d1i <- sd(tbl_both$d1i)
mean_d2i <- mean(tbl_both$d2i)
sd_d2i <- sd(tbl_both$d2i)


tbl_train <- tbl_both %>% filter(session == "train")
tbl_transfer <- tbl_both %>% filter(session == "transfer")

if (!is_saved) {
  
  # save train, transfer, and combined data as rds and csv
  
  saveRDS(tbl_both, file = "data/infpro_task-cat_beh/tbl_both.RDS")
  saveRDS(tbl_train, file = "data/infpro_task-cat_beh/tbl_train.RDS")
  saveRDS(tbl_transfer, file = "data/infpro_task-cat_beh/tbl_transfer.RDS")
  
  write_csv(tbl_train, file = "data/infpro_task-cat_beh/tbl_train.csv")
  write_csv(tbl_transfer, file = "data/infpro_task-cat_beh/tbl_transfer.csv")
  write_csv(tbl_both, file = "data/infpro_task-cat_beh/tbl_both.csv")
}



tbl_stim_id <- tbl_train %>% count(d1i, d2i, d1i_z, d2i_z, category) %>%
  arrange(d1i, d2i) %>% mutate(stim_id = seq_along(d1i + d2i)) %>%
  dplyr::select(-n)
tbl_stim_id_transfer <- tbl_transfer %>% count(d1i, d2i, d1i_z, d2i_z, category) %>%
  arrange(d1i, d2i) %>% mutate(stim_id = seq_along(d1i + d2i)) %>%
  dplyr::select(-n)
tbl_train <- tbl_train %>% 
  left_join(tbl_stim_id, by = c("d1i", "d2i", "d1i_z", "d2i_z", "category")) %>%
  relocate(stim_id, .before = d1i)
tbl_transfer <- tbl_transfer %>%
  left_join(tbl_stim_id_transfer, by = c("d1i", "d2i", "d1i_z", "d2i_z", "category")) %>%
  relocate(stim_id, .before = d1i)

# define how many trials starting from the last trial should be analyzed
n_last_trials <- 500

tbl_train_last <- tbl_train %>% group_by(participant) %>%
  mutate(
    rwn_fwd = row_number(block),
    rwn_bkwd = row_number(desc(rwn_fwd))
  ) %>% ungroup() %>%
  filter(rwn_bkwd <= n_last_trials) %>%
  dplyr::select(-c(rwn_fwd, rwn_bkwd))

tbl_both <- rbind(tbl_train_last, tbl_transfer)

# Plot Overall Proportion Responses By Stimulus and Category --------------

# only correct responses
pl_train <- plot_average_categorization_accuracy(tbl_train_last, "Train")
pl_tf <- plot_average_categorization_accuracy(tbl_transfer, "Transfer")
marrangeGrob(list(pl_train, pl_tf), ncol = 2, nrow = 1)

# Aggregate table with length = participants*categories*stimIDs
tbl_train_agg <- aggregate_by_stimulus_and_response(tbl_stim_id, tbl_train_last)
tbl_transfer_agg <- aggregate_by_stimulus_and_response(tbl_stim_id_transfer, tbl_transfer)
tbl_train_agg_overall <- tbl_train_agg %>%
  group_by(d1i, d2i, d1i_z, d2i_z, stim_id, category, response) %>%
  summarize(
    n_responses = sum(n_responses),
    n_trials = sum(n_trials)
  ) %>%
  mutate(prop_responses = n_responses / n_trials)

tbl_transfer_agg_overall <- tbl_transfer_agg %>%
  group_by(d1i, d2i, d1i_z, d2i_z, stim_id, category, response) %>%
  summarize(
    n_responses = sum(n_responses),
    n_trials = sum(n_trials)
  ) %>%
  mutate(prop_responses = n_responses / n_trials)

# all responses
participant_sample <- "Average of All"
plot_proportion_responses(
  tbl_train_agg_overall %>% 
    mutate(response = str_c("Response = ", response)) %>%
    filter(prop_responses > .025),
  participant_sample,
  facet_by_response = TRUE
)
plot_proportion_responses(
  tbl_transfer_agg_overall %>% 
    mutate(response = str_c("Response = ", response)) %>%
    filter(prop_responses > .025),
  participant_sample,
  facet_by_response = TRUE
)

tbl_train_agg$response_int <- as.numeric(factor(
  tbl_train_agg$response, levels = c("A", "B", "C"), ordered = TRUE
))
tbl_transfer_agg$response_int <- as.numeric(factor(
  tbl_transfer_agg$response, levels = c("A", "B", "C"), ordered = TRUE
))
tbl_train_agg$category_int <- as.numeric(factor(
  tbl_train_agg$category, levels = c("A", "B", "C"), ordered = TRUE
))
tbl_transfer_agg$category_int <- as.numeric(factor(
  tbl_transfer_agg$category, levels = c("A", "B", "C"), ordered = TRUE
))



# General settings --------------------------------------------------------


# mcmc settings for all models

l_stan_params <- list(
  n_samples = 1000,
  n_warmup = 250,
  n_chains = 3
)


# GCM ---------------------------------------------------------------------

tbl_both_agg <- rbind(tbl_train_agg, tbl_transfer_agg)
l_tbl_both_agg <- split(tbl_both_agg, tbl_both_agg$participant)

if (!is_saved) {
  stan_gcm <- write_gcm_stan_file_predict()
  mod_gcm <- cmdstan_model(stan_gcm)
  safe_gcm <- safely(bayesian_gcm)
  
  n_workers_available <- parallel::detectCores()
  plan(multisession, workers = n_workers_available - 2)
  
  options(warn = -1)
  l_loo_gcm <- furrr::future_map(
    l_tbl_both_agg, safe_gcm, 
    l_stan_params = l_stan_params, 
    mod_gcm = mod_gcm, 
    .progress = TRUE
  )
  options(warn = 0)
  plan("sequential")
  saveRDS(l_loo_gcm, file = "data/infpro_task-cat_beh/gcm-loos.RDS")
  
} else {
  l_loo_gcm <- readRDS(file = "data/infpro_task-cat_beh/gcm-loos.RDS")
}


# ok
l_gcm_results <- map(l_loo_gcm, "result")
# not ok
map(l_loo_gcm, "error") %>% reduce(c)



# Prototype: Multivariate Gaussian ---------------------------------------

l_tbl_both <- split(tbl_both, tbl_both$participant)

if (!is_saved) {
  stan_gaussian <- write_gaussian_naive_bayes_stan()
  mod_gaussian <- cmdstan_model(stan_gaussian)
  safe_gaussian <- safely(bayesian_gaussian_naive_bayes)
  
  n_workers_available <- parallel::detectCores()
  plan(multisession, workers = n_workers_available - 2)
  
  l_loo_gaussian <- furrr::future_map2(
    l_tbl_both, l_tbl_both_agg, safe_gaussian, 
    l_stan_params = l_stan_params,
    mod_gaussian = mod_gaussian, 
    .progress = TRUE
  )
  plan("sequential")
  saveRDS(l_loo_gaussian, file = "data/infpro_task-cat_beh/gaussian-loos.RDS")
  
} else {
  l_loo_gaussian <- readRDS(file = "data/infpro_task-cat_beh/gaussian-loos.RDS")
}

# ok
l_gaussian_results <- map(l_loo_gaussian, "result")
# not ok
map(l_loo_gaussian, "error") %>% reduce(c)


# Prototype: Multi with Correlations

if (!is_saved) {
  stan_multi <- write_gaussian_multi_bayes_stan()
  mod_multi <- cmdstan_model(stan_multi)
  safe_multi <- safely(bayesian_gaussian_multi_bayes)
  
  n_workers_available <- parallel::detectCores()
  plan(multisession, workers = n_workers_available - 2)
  
  l_loo_multi <- furrr::future_map2(
    l_tbl_both, l_tbl_both_agg, safe_multi, 
    l_stan_params = l_stan_params,
    mod_multi = mod_multi, 
    .progress = TRUE
  )
  plan("sequential")
  
  saveRDS(l_loo_multi, file = "data/infpro_task-cat_beh/multi-loos.RDS")
  
} else {
  l_loo_multi <- readRDS(file = "data/infpro_task-cat_beh/multi-loos.RDS")
  
}

# ok
l_multi_results <- map(l_loo_multi, "result")
# not ok
map(l_loo_multi, "error") %>% reduce(c)



# Model Weights Prototype 1 vs. Prototype 2 ------------------------------

safe_weights <- safely(loo_model_weights)

l_loo_weights_prototype_comparison <- pmap(
  list(l_gaussian_results, l_multi_results), # 
  ~ safe_weights(list(..1, ..2)), 
  method = "stacking"
)
l_loo_weights_prototype_comparison



# Model Weights Exemplar vs. Prototype ------------------------------------


l_loo_weights <- pmap(
  list(l_gcm_results, l_gaussian_results), # 
  ~ safe_weights(list(..1, ..2)), 
  method = "stacking"
)
l_loo_weights_results <- map(l_loo_weights, ~ .x$"result"[2])
v_weights <- l_loo_weights_results[map_lgl(l_loo_weights_results, ~ !is.null(.x))] %>% 
  unlist()
participants <- str_match(names(v_weights), "^([0-9]*).model2")[,2]
tbl_weights <- tibble(
  participant = participants,
  weight_prototype = v_weights
)


ggplot(tbl_weights, aes(weight_prototype)) + 
  geom_histogram(fill = "#66CCFF", color = "white") +
  theme_bw() +
  labs(x = "Model Weight Prototype Model", y = "Nr. Participants")

saveRDS(tbl_weights, file = "data/infpro_task-cat_beh/model-weights.rds")


# color weights according to train/transfer performance
tbl_transfer_participant_avg <- tbl_transfer_agg %>% 
  filter(category == response) %>%
  group_by(participant) %>%
  summarise(n_trials = sum(n_trials), n_responses = sum(n_responses)) %>%
  ungroup() %>%
  mutate(
    prop_correct = n_responses / n_trials,
    participant = as.character(participant)
  )

tbl_weights <- tbl_weights %>% 
  left_join(tbl_transfer_participant_avg, by = "participant")

ggplot(tbl_weights, aes(weight_prototype, group = prop_correct)) + 
  geom_histogram(color = "white", aes(fill = prop_correct)) +
  theme_bw() +
  scale_fill_gradient(low = "#FF6600", high = "#009966") +
  labs(x = "Model Weight Prototype Model", y = "Nr. Participants")

ggplot(tbl_weights, aes(weight_prototype, prop_correct)) +
  geom_point(shape = 1) +
  geom_smooth(method = "lm") +
  geom_hline(yintercept = .33, linetype = "dotdash", color = "grey88", size = .75) +
  coord_cartesian(ylim = c(.3, .9)) +
  theme_bw() +
  labs(x = "Model Weight Prototype Model", y = "Prop. Correct Transfer")

# Distribution of Model Parameters ----------------------------------------

search_words <- c("gcm-summary", "gaussian-summary")
model_dir <- dir("data/infpro_task-cat_beh/models/")
path_summary <- map(search_words, ~ str_c("data/infpro_task-cat_beh/models/", model_dir[startsWith(model_dir, .x)]))

# gcm
l_summary_gcm <- map(path_summary[[1]], readRDS)
# participants have a response bias for categories 1 and 2 (i.e., the target categories)
map(l_summary_gcm, ~ .x[str_starts(.x$variable, "b|c"), ]) %>%
  reduce(rbind) %>%
  ggplot(aes(mean)) +
  geom_histogram(fill = "#66CCFF", color = "white") +
  facet_wrap(~ variable, scales = "free") +
  theme_bw() +
  labs(
    x = "MAP",
    y = "Nr. Participants"
  )

# prototype
l_summary_prototype <- map(path_summary[[2]], readRDS)
# participants have a response bias for categories 1 and 2 (i.e., the target categories)
map(l_summary_prototype, ~ .x[str_starts(.x$variable, "mu|sigma|c"), ]) %>%
  reduce(rbind) %>%
  ggplot(aes(mean)) +
  geom_histogram(fill = "#66CCFF", color = "white") +
  facet_wrap(~ variable, scales = "free", ncol = 3) +
  theme_bw() +
  labs(
    x = "MAP",
    y = "Nr. Participants"
  )

# Gaussian

l_summary_gaussian <- map(path_summary[[2]], readRDS)
tbl_summaries <- l_summary_gaussian %>% reduce(rbind)
mean_representation <- function(cat, tbl_summary){
  var1 <- str_c("mu1[", cat, "]")
  var2 <- str_c("mu2[", cat, "]")
  tbl_summary %>% filter(variable == var1 | variable == var2) %>%
    select(c(participant, variable, mean)) %>%
    pivot_wider(names_from = "variable", values_from = "mean") %>%
    mutate(category = cat) %>%
    rename(x_z = var1, y_z = var2)
}

response_biases <- function(tbl_summary){
  tbl_summary %>% filter(variable == "cat_prior[1]" | variable == "cat_prior[2]" | variable == "cat_prior[3]") %>%
    dplyr::select(c(participant, variable, mean)) %>%
    pivot_wider(names_from = "variable", values_from = "mean")
}

tbl_all <- map(c(1, 2, 3), mean_representation, tbl_summary = tbl_summaries) %>%
  reduce(rbind) %>%
  mutate(
    x = x_z * sd_d1i + mean_d1i,
    y = y_z * sd_d2i + mean_d2i,
    category = factor(category, labels = 1:3)
  )

response_biases(tbl_summaries) %>%
  pivot_longer(cols = -participant) %>%
  ggplot(aes(value)) +
  geom_histogram(fill = "#66CCFF", color = "white") +
  facet_wrap(~ name) +
  theme_bw() 

pl <- ggplot(tbl_all, aes(x, y, group = category)) +
  geom_point(shape = 1, size = 2, aes(color = category)) +
  geom_density2d(aes(color = category)) +
  theme_bw() +
  theme(plot.title = element_text(size = 10)) +
  scale_color_brewer(palette = "Set1", name = "Category") +
  labs(
    x = "Head Spikiness",
    y = "Belly Size"
  )
ggExtra::ggMarginal(pl, groupFill = TRUE, type = "histogram")
saveRDS(tbl_all, file = "data/infpro_task-cat_beh/gaussian-participant-maps.rds")


map(l_loo_weights, "result") %>% reduce(rbind) %>%
  as_tibble() %>%
  pivot_longer(starts_with("model")) %>%
  ggplot(aes(value)) +
  geom_histogram() +
  facet_wrap(~ name)

tbl_biases <- response_biases(tbl_summaries) %>%
  pivot_longer(-participant, names_to = "variable", values_to = "mean") %>%
  mutate(
    variable = factor(variable, labels = c("Bias Category 1", "Bias Category 2", "Bias Category 3")),
    model = "Gaussian"
  ) %>% rbind(
    map(l_summary_gcm, ~ .x[str_starts(.x$variable, "b"), ]) %>%
      reduce(rbind) %>% dplyr::select(c(participant, variable, mean)) %>%
      mutate(
        variable = factor(variable, labels = c("Bias Category 1", "Bias Category 2", "Bias Category 3")),
        model = "GCM"
      )    
  )

tbl_biases %>%
  ggplot(aes(mean)) +
  geom_histogram() +
  facet_grid(model ~ variable) +
  geom_histogram(fill = "#66CCFF", color = "white") +
  theme_bw()

# biases correspond between models
tbl_biases %>% 
  pivot_wider(id_cols = c(participant, variable), names_from = model, values_from = mean) %>%
  ggplot(aes(Gaussian, GCM)) +
  geom_smooth(method = "lm", se = FALSE, color = "#66CCFF") +
  geom_point() +
  facet_wrap(~ variable) +
  theme_bw()
