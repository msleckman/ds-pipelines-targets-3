## Load packages for targets script
library(targets)
library(tarchetypes)
library(tibble)
library(retry)
suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(dplyr))

## Load packages needed by functions below
options(tidyverse.quiet = TRUE)
tar_option_set(packages = c("tidyverse",
                            "dataRetrieval",
                            "urbnmapr",
                            "rnaturalearth",
                            "cowplot",
                            "lubridate",
                            'leaflet',
                            'leafpop',
                            'htmlwidgets')
               )

# Load functions needed by targets below
source("1_fetch/src/find_oldest_sites.R")
source("1_fetch/src/get_site_data.R")
source("3_visualize/src/map_sites.R")
source("2_process/src/tally_site_obs.R")
source("2_process/src/summarize_targets.R")
source("3_visualize/src/plot_site_data.R")
source("3_visualize/src/plot_data_coverage.R")
source('3_visualize/src/map_timeseries.R')

## create log folder
dir.create('3_visualize/log/', showWarnings = F)

## Configuration - define global vars
states <- c('AL','AZ','AR','CA','CO','CT','DE','DC','FL','GA','ID','IL','IN','IA',
            'KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV','NH',
            'NJ','NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN','TX',
            'UT','VT','VA','WA','WV','WI','WY','AK','HI','GU','PR')

parameter <- c('00060')

## Structure static branching Targets with tar_map()

mapped_by_state_targets <- tar_map(
  # Use state as suffix in branch target naming
  names = state_abb,
  # Use unlist = F so that we can reference only the branch targets from
  unlist = FALSE,
  # Task names passed into tar_map() via arg. 'values='
  values = tibble(state_abb = states) %>%
    mutate(state_plot_files = sprintf("3_visualize/out/timeseries_%s.png", state_abb)),

  # Target 1 - Subset to states in selected states list
  tar_target(nwis_inventory, dplyr::filter(oldest_active_sites,
                                           state_cd == state_abb)),
  #Target 2 - Download data for given site
  tar_target(nwis_data, retry::retry(get_site_data(nwis_inventory,
                                      state_abb,
                                      parameter), when = "Ugh, the internet data transfer failed!",
                                     max_tries = 30)),
  # Target 3 - Clean and summarize data for each state
  tar_target(tally, tally_site_obs(nwis_data)),

  # Target 4 - Produce timeseries plot for each state
  tar_target(timeseries_png, plot_site_data(out_file = state_plot_files,
                                            site_data = nwis_data,
                                            parameter = parameter),
             format = "file")
)

## List of Targets
list(
  # Identify oldest sites in NWIS data
  tar_target(oldest_active_sites, find_oldest_sites(states, parameter)),

  # Pull all targets in the tar_map() above
  mapped_by_state_targets,

  # Combine all state obs tallies (output of tar_map() )
  tar_combine(obs_tallies, mapped_by_state_targets$tally,
              command = combine_obs_tallies(!!!.x)),

  # Export log file of timeseries outputs
  tar_combine(summary_state_timeseries_csv, mapped_by_state_targets$timeseries_png,
    command = summarize_targets('3_visualize/log/summary_state_timeseries.csv', !!!.x),
    format="file"
  ),

  # Plot data coverage graphic
  tar_target(data_coverage_png, plot_data_coverage(oldest_site_tallies = obs_tallies,
                                                   out_file = "3_visualize/out/data_coverage.png",
                                                   parameter = parameter),
             format = 'file'),

  # Map selected oldest sites
  tar_target(site_map_png,
             map_sites("3_visualize/out/site_map.png",
                       oldest_active_sites),
    format = "file"
  ),

  # Map selected oldest sites on a interactive html
  tar_target(timeseries_map_html,
             map_timeseries(site_info = oldest_active_sites,
                            plot_info_csv = summary_state_timeseries_csv,
                            out_file = '3_visualize/out/timeseries_map.html'),
             format = 'file')

)
