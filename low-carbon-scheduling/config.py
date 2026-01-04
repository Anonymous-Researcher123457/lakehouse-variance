from src.scheduler import FIFOScheduler, GreedyLowCarbonDeferScheduler

# =====================  FILEPATHS  =====================

# CI Signals
GR_carbon_csv_path               = "./CI_data/GR_2024_5_minute.csv"
GB_carbon_csv_path               = "./CI_data/GB_2024_5_minute.csv"
BRA_carbon_csv_path              = "./CI_data/BR_2024_5_minute.csv"
CY_carbon_csv_path               = "./CI_data/AU_2024_5_minute.csv"

csv_list                         = [GR_carbon_csv_path,  
                                    GB_carbon_csv_path, 
                                    BRA_carbon_csv_path, 
                                    CY_carbon_csv_path, 
                                   ]

# Baseline Runtime Values
baseline_GNN_values_csv_path     = f"../Traces/zero-shot-cost-estimation/Baseline_TPCDS_MSELoss_3090/values.csv"
baseline_RF_values_csv_path      = f"../Traces/Random_Forrest/Baseline_tpcds/values.csv"

# Local Runtime Values
local_GNN_values_csv_path        = f"../Traces/zero-shot-cost-estimation/Local_TPCDS_MSELoss_3090/values.csv"
local_RF_values_csv_path         = f"../Traces/Random_Forrest/Local_tpcds/values.csv"


# =====================  SIMULATOR  =====================

POWER_CONSUMPTION                = 0.150 # kw
START_DATE                       = "2024-11-9"
END_DATE                         = "2024-11-14"
TIME                             = "19:00:00"
NUM_QUERIES                      = 750
USE_LIFECYCLE                    = True
SLOT_SEC                         = 1
SEARCH_HOURS                     = 12
SEED                             = 0

# =====================  SCHEDULERS  =====================

fifo_scheduler                   = FIFOScheduler(random_seed=SEED)

# Greedy params
BASE_CAN_STEP_SLOTS              = 3600
candidate_step_slots             = int(round(BASE_CAN_STEP_SLOTS/ SLOT_SEC))

greedy_defer_order_scheduler     = GreedyLowCarbonDeferScheduler(
                                     name="Greedy Delay",
                                     search_hours=SEARCH_HOURS,
                                     candidate_step_slots=candidate_step_slots,  
                                     show_progress=True,         
                                 )

# Local-Search params
SWAP_PROB                        = 0.5
MAX_ITERS                        = 5000
MAX_SHIFT_SLOTS                  = 86400

schedulers                       = [fifo_scheduler, greedy_defer_order_scheduler]