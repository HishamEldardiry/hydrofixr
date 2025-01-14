#' generate_parameters
#'
#' @param year year to be generated
#' @param resolution resolution of output ("weekly", "monthly")
#' @param data_dir data directory containing hydrofixr consolidated inputs
#' @param WM_case path to WM simulation results
#' @description gets p_mean, p_max, p_min for given water input, defined by year
#' @importFrom dplyr filter select left_join mutate bind_rows mutate_if
#' @return tibble of pmean, pmax, pmin for CONUS dams using parameters from CRB 
#' @export
#'
generate_parameters <- function(year = 2009,
                                     resolution = "monthly",
                                     data_dir,
                                     WM_case = "/WM_dev_base_case_cropped/"){

  message("Starting parameter generation. This may take a few minutes...")

  if(resolution == "monthly"){
    message("Getting monthly average generation estimates...")
        get_pmean(pcm = "none", NERC = NULL,
                  data_dir = data_dir,
                  WM_case = WM_case,
                  mode = resolution, hyd_year = year) ->
          pmean_monthly_x


        message(" | Computing pmax and pmin parameters")
        pmean_monthly_x %>%
          left_join(get_pmax_pmin_predictions(zone='CRB',data_dir=data_dir), by = "EIA_ID") %>%
          left_join(read_HydroSource(data_dir=data_dir) %>%
                      select(EIA_ID, nameplate_HS = CH_MW, plant, state, bal_auth, mode),
                    by = "EIA_ID") %>% #mutate(month = match(month, month.abb)) %>%
          append_capabilities(data_dir=data_dir,"monthly") %>%
          mutate(capability = if_else(is.na(capability),nameplate_EIA, capability)) %>%
          mutate(pmean_MW = if_else(pmean_MW > capability, capability, pmean_MW)) %>%
          mutate(pmax = pmean_MW + (max_param * (capability - pmean_MW)),
                 pmin = pmean_MW * min_param) %>%
          select(EIA_ID, plant, state, bal_auth, mode, year, month,
                 mean = pmean_MW, max = pmax, min = pmin, capability, nameplate_HS, nameplate_EIA) ->
          p_all_basic
		
		
		# since data for CRB is available, then no need to use the interpolation (linear model) approach. So use the actual data for CRB (without using the get_pmax_pmin_predictions()  function) 
        get_pmax_pmin_params("CRB", resolution, data_dir=data_dir,smooth_params = FALSE) %>%
          left_join(pmean_monthly_x, by = c("EIA_ID", "month")) %>%
          left_join(read_HydroSource(data_dir=data_dir) %>% select(EIA_ID, nameplate_HS = CH_MW, plant, state, bal_auth, mode),
                    by = "EIA_ID") %>% #mutate(month = match(month, month.abb)) %>%
           append_capabilities(data_dir=data_dir,"monthly") %>%
          mutate(pmax = pmean_MW + (max_param * (capability - pmean_MW)),
                 pmin = pmean_MW * min_param) %>%
          select(EIA_ID, plant, state, bal_auth, mode, year, month,
                 mean = pmean_MW, max = pmax, min = pmin, capability, nameplate_HS, nameplate_EIA) ->
          p_CRB

        p_all_basic %>%
          filter(!EIA_ID %in% p_CRB[["EIA_ID"]]) %>%    # replace CRB plants with the p_CRB rows which have more reliable data than using the get_pmax_pmin_predictions() function
          bind_rows(p_CRB) %>%
          mutate(year = as.integer(year), EIA_ID = as.character(EIA_ID)) %>%
          mutate_if(is.double, round, 3) %>%
          left_join(tibble(month = month.abb), by = "month") %>%
          select(EIA_ID, plant, state, bal_auth, mode, year, month,
                 mean, max, min, capability, nameplate_EIA,nameplate_HS) ->
          p_all_monthly

        return(p_all_monthly)

  }

  if(resolution == "weekly"){

    message(" | Getting weekly average generation estimates...")
    get_pmean(pcm = "none", NERC = NULL, WM_results_dir = WM_results_dir,
              mode = "weekly", hyd_year = year) -> pmean_weekly_x

    message(" | Computing pmax and pmin parameters")
    pmean_weekly_x %>%
      left_join(get_pmax_pmin_predictions(), by = "EIA_ID") %>%
      left_join(read_HydroSource(data_dir=data_dir) %>% select(EIA_ID, nameplate_HS = CH_MW, plant, state, bal_auth, mode),
                by = "EIA_ID") %>%
      append_capabilities(data_dir=data_dir,"weekly") %>%
      mutate(capability = if_else(is.na(capability), nameplate_EIA, capability)) %>%
      mutate(pmean_MW = if_else(pmean_MW > capability, capability, pmean_MW)) %>%
      mutate(pmax = pmean_MW + (max_param * (capability - pmean_MW)),
             pmin = pmean_MW * min_param) %>%
      select(EIA_ID, plant, state, bal_auth, mode, year, epiweek,
             mean = pmean_MW, max = pmax, min = pmin, capability, nameplate_EIA, nameplate_HS) ->
      p_all_basic

    get_pmax_pmin_params("CRB", "weekly", smooth_params = TRUE) %>%
      left_join(read_HydroSource(data_dir=data_dir) %>%
                  select(EIA_ID, nameplate_HS = CH_MW, plant, state, bal_auth, mode),
                by = "EIA_ID") %>%
      append_capabilities(data_dir=data_dir,"weekly") %>%
      left_join(pmean_weekly_x, by = c("EIA_ID", "epiweek")) %>%
      rowwise() %>%
      mutate(
        pmax = min(pmean_MW + (max_param * (capability - pmean_MW)), capability),
        pmin = max(pmean_MW * min_param, 0)
        ) %>% ungroup() %>%
      select(EIA_ID, plant, state, bal_auth, mode, year, epiweek,
             mean = pmean_MW, max = pmax, min = pmin, capability, nameplate_EIA, nameplate_HS) ->
      p_CRB

    p_all_basic %>%
      filter(!EIA_ID %in% p_CRB[["EIA_ID"]]) %>%
      bind_rows(p_CRB) %>%
      mutate(year = as.integer(year),
             epiweek = as.integer(epiweek),
             EIA_ID = as.character(EIA_ID)) %>%
      mutate_if(is.double, round, 3) ->
      p_all_weekly

    return(p_all_weekly)

  }
}
