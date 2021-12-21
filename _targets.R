library(targets)
library(tarchetypes)
library(tibble)
suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(dplyr))

options(tidyverse.quiet = TRUE)
tar_option_set(packages = c("tidyverse",
                            "dataRetrieval",
                            "urbnmapr",
                            "rnaturalearth",
                            "cowplot",
                            "lubridate"))

# Load functions needed by targets below
source("1_fetch/src/find_oldest_sites.R")
source("1_fetch/src/get_site_data.R")
source("3_visualize/src/map_sites.R")
source("2_process/src/tally_site_obs.R")
source("2_process/src/summarize_targets.R")
source("3_visualize/src/plot_site_data.R")
source("3_visualize/src/plot_data_coverage.R")
source('3_visualize/src/map_timeseries.R')


# create log folder
dir.create('3_visualize/log/', showWarnings = F)

# Configuration
states <- c('WI','MN','MI','IL', 'IA')
parameter <- c('00060')

## static branching with tar_map()
mapped_by_state_targets <- tar_map(
  ## Use state as suffix in branch target naming
  names = state_abb,
  ## Use unlist = F so that we can reference only the branch targets from
  unlist = FALSE,
  ## Task names passed into tar_map() via arg. 'values='
  values = tibble(state_abb = states) %>%
    mutate(state_plot_files = sprintf("3_visualize/out/timeseries_%s.png", state_abb)),

  tar_target(nwis_inventory, dplyr::filter(oldest_active_sites,
                                           state_cd == state_abb)),

  tar_target(nwis_data, get_site_data(nwis_inventory,
                                      state_abb,
                                      parameter)),

  tar_target(tally, tally_site_obs(nwis_data)),

  tar_target(timeseries_png, plot_site_data(out_file = state_plot_files,
                                            site_data = nwis_data,
                                            parameter = parameter),
             format = "file")
)

# Targets
list(
  # Identify oldest sites
  tar_target(oldest_active_sites, find_oldest_sites(states, parameter)),

  mapped_by_state_targets, # put tally target as input, check if correct

  tar_combine(obs_tallies, mapped_by_state_targets$tally, command = combine_obs_tallies(!!!.x)),

  tar_combine(
    summary_state_timeseries_csv,
    mapped_by_state_targets$timeseries_png,
    command = summarize_targets('3_visualize/log/summary_state_timeseries.csv', !!!.x),
    format="file"
  ),

  tar_target(data_coverage_png, plot_data_coverage(oldest_site_tallies = obs_tallies,
                                                   out_file = "3_visualize/out/data_coverage.png",
                                                   parameter = parameter),
             format = 'file'),

  # Map oldest sites
  tar_target(site_map_png,
             map_sites("3_visualize/out/site_map.png",
                       oldest_active_sites),
    format = "file"
  )

)
