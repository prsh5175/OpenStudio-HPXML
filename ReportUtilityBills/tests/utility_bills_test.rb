# frozen_string_literal: true

require 'oga'
require_relative '../../HPXMLtoOpenStudio/resources/minitest_helper'
require_relative '../../HPXMLtoOpenStudio/resources/constants'
require_relative '../../HPXMLtoOpenStudio/resources/energyplus'
require_relative '../../HPXMLtoOpenStudio/resources/hpxml'
require_relative '../../HPXMLtoOpenStudio/resources/hpxml_defaults'
require_relative '../../HPXMLtoOpenStudio/resources/schedules'
require_relative '../../HPXMLtoOpenStudio/resources/unit_conversions'
require_relative '../../HPXMLtoOpenStudio/resources/xmlhelper'
require_relative '../resources/util.rb'
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require_relative '../measure.rb'
require 'csv'

class ReportUtilityBillsTest < MiniTest::Test
  # BEopt 2.9.0.0:
  # - Standard, New Construction, Single-Family Detached
  # - 600 sq ft (30 x 20)
  # - EPW Location: USA_CO_Denver.Intl.AP.725650_TMY3.epw
  # - Cooking Range: Propane
  # - Water Heater: Oil Standard
  # - PV System: None, 1.0 kW, 10.0 kW
  # - Timestep: 60 min
  # - User-Specified rates (calculated using default value):
  #   - Electricity: 0.1195179675994109 $/kWh
  #   - Natural Gas: 0.7734017611590879 $/therm
  #   - Fuel Oil: 3.495346153846154 $/gal
  #   - Propane: 2.4532692307692305 $/gal
  # - Sample Tiered Rate
  #   - Tier 1: 150 Max kWh
  #   - Tier 2: 300 Max kWh
  # - Sample Tiered Time-of-Use Rate
  #   - Tier 1: 150 Max kWh (Period 1 and 2)
  #   - Tier 2: 300 Max kWh (Period 2)
  # - All other options left at default values
  # Then retrieve 1.csv from output folder, copy it, rename it

  def before_setup
    @args_hash = {}
    @args_hash['electricity_bill_type'] = 'Simple'
    @args_hash['electricity_fixed_charge'] = 8.0
    @args_hash['natural_gas_fixed_charge'] = 8.0
    @args_hash['wood_cord_marginal_rate'] = 0.015
    @args_hash['wood_pellets_marginal_rate'] = 0.015
    @args_hash['coal_marginal_rate'] = 0.015
    @args_hash['pv_compensation_type'] = 'Net Metering'
    @args_hash['pv_annual_excess_sellback_rate_type'] = 'User-Specified'
    @args_hash['pv_net_metering_annual_excess_sellback_rate'] = 0.03
    @args_hash['pv_feed_in_tariff_rate'] = 0.12
    @args_hash['pv_grid_connection_fee_units'] = '$/kW'
    @args_hash['pv_monthly_grid_connection_fee'] = 0.0

    # From BEopt Output screen (Utility Bills $/yr)
    @expected_bills = {
      'Electricity: Fixed ($)' => 96,
      'Electricity: Marginal ($)' => 632,
      'Electricity: PV Credit ($)' => 0,
      'Natural Gas: Fixed ($)' => 96,
      'Natural Gas: Marginal ($)' => 149,
      'Fuel Oil: Total ($)' => 462,
      'Propane: Total ($)' => 76,
      'Wood Cord: Total ($)' => 0,
      'Wood Pellets: Total ($)' => 0,
      'Coal: Total ($)' => 0
    }

    @measure = ReportUtilityBills.new
    @hpxml_path = File.join(File.dirname(__FILE__), '../../workflow/sample_files/base-pv.xml')
    @hpxml = HPXML.new(hpxml_path: @hpxml_path)
    HPXMLDefaults.apply_header(@hpxml, nil)

    @measure_bills_csv = File.join(File.dirname(__FILE__), 'results_bills.csv')
    FileUtils.rm_rf(@measure_bills_csv)

    @template_osw = File.join(File.dirname(__FILE__), '..', '..', 'workflow', 'template-run-hpxml.osw')
    @workflow_bills_csv = File.join(File.dirname(@template_osw), 'run', 'results_bills.csv')
    FileUtils.rm_rf(@workflow_bills_csv)
  end

  # Simple Calculations

  def test_simple_calculations_pv_none
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_None.csv')
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, [])
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_simple_calculations_pv_1kW
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: PV Credit ($)'] = -177
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_simple_calculations_pv_10kW
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: PV Credit ($)'] = -920
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_simple_calculations_pv_10kW_retail
    @args_hash['pv_annual_excess_sellback_rate_type'] = 'Retail Electricity Cost'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: PV Credit ($)'] = -1777
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_simple_calculations_pv_1kW_feed_in_tariff
    @args_hash['pv_compensation_type'] = 'Feed-In Tariff'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: PV Credit ($)'] = -178
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_simple_calculations_pv_10kW_feed_in_tariff
    @args_hash['pv_compensation_type'] = 'Feed-In Tariff'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: PV Credit ($)'] = -1785
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_simple_calculations_pv_1kW_grid_fee_dollars_per_kW
    @args_hash['pv_monthly_grid_connection_fee'] = 2.50
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 126
    @expected_bills['Electricity: PV Credit ($)'] = -177
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_simple_calculations_pv_1kW_grid_fee_dollars
    @args_hash['pv_grid_connection_fee_units'] = '$'
    @args_hash['pv_monthly_grid_connection_fee'] = 7.50
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 186
    @expected_bills['Electricity: PV Credit ($)'] = -177
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  # Detailed Calculations

  # Tiered

  def test_detailed_calculations_sample_tiered_pv_none
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Rate'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_None.csv')
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, [])
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 577
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_pv_1kW
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Rate'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 577
    @expected_bills['Electricity: PV Credit ($)'] = -190
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_pv_10kW
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Rate'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 577
    @expected_bills['Electricity: PV Credit ($)'] = -576
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_pv_10kW_retail
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Rate'
    @args_hash['pv_annual_excess_sellback_rate_type'] = 'Retail Electricity Cost'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 577
    @expected_bills['Electricity: PV Credit ($)'] = -1442
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_pv_1kW_feed_in_tariff
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Rate'
    @args_hash['pv_compensation_type'] = 'Feed-In Tariff'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 577
    @expected_bills['Electricity: PV Credit ($)'] = -178
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_pv_10kW_feed_in_tariff
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Rate'
    @args_hash['pv_compensation_type'] = 'Feed-In Tariff'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 577
    @expected_bills['Electricity: PV Credit ($)'] = -1786
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_pv_1kW_grid_fee_dollars_per_kW
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Rate'
    @args_hash['pv_monthly_grid_connection_fee'] = 2.50
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 138
    @expected_bills['Electricity: Marginal ($)'] = 577
    @expected_bills['Electricity: PV Credit ($)'] = -190
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_pv_1kW_grid_fee_dollars
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Rate'
    @args_hash['pv_grid_connection_fee_units'] = '$'
    @args_hash['pv_monthly_grid_connection_fee'] = 7.50
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 198
    @expected_bills['Electricity: Marginal ($)'] = 577
    @expected_bills['Electricity: PV Credit ($)'] = -190
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  # Time-of-Use

  def test_detailed_calculations_sample_tou_pv_none
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Time-of-Use Rate'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_None.csv')
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, [])
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 391
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tou_pv_1kW
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Time-of-Use Rate'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 391
    @expected_bills['Electricity: PV Credit ($)'] = -111
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tou_pv_10kW
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Time-of-Use Rate'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 391
    @expected_bills['Electricity: PV Credit ($)'] = -391
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tou_pv_10kW_retail
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Time-of-Use Rate'
    @args_hash['pv_annual_excess_sellback_rate_type'] = 'Retail Electricity Cost'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 391
    @expected_bills['Electricity: PV Credit ($)'] = -1115
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tou_pv_1kW_feed_in_tariff
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Time-of-Use Rate'
    @args_hash['pv_compensation_type'] = 'Feed-In Tariff'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 391
    @expected_bills['Electricity: PV Credit ($)'] = -178
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tou_pv_10kW_feed_in_tariff
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Time-of-Use Rate'
    @args_hash['pv_compensation_type'] = 'Feed-In Tariff'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 391
    @expected_bills['Electricity: PV Credit ($)'] = -1787
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tou_pv_1kW_grid_fee_dollars_per_kW
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Time-of-Use Rate'
    @args_hash['pv_monthly_grid_connection_fee'] = 2.50
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 138
    @expected_bills['Electricity: Marginal ($)'] = 391
    @expected_bills['Electricity: PV Credit ($)'] = -111
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tou_pv_1kW_grid_fee_dollars
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Time-of-Use Rate'
    @args_hash['pv_grid_connection_fee_units'] = '$'
    @args_hash['pv_monthly_grid_connection_fee'] = 7.50
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 198
    @expected_bills['Electricity: Marginal ($)'] = 391
    @expected_bills['Electricity: PV Credit ($)'] = -111
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  # Tiered and Time-of-Use
  # FIXME: get expected values from BEopt

  def test_detailed_calculations_sample_tiered_tou_pv_none
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Time-of-Use Rate'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_None.csv')
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, [])
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 376
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_tou_pv_1kW
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Time-of-Use Rate'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 376
    @expected_bills['Electricity: PV Credit ($)'] = -107
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_tou_pv_10kW
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Time-of-Use Rate'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 379
    @expected_bills['Electricity: PV Credit ($)'] = -379 # FIXME 377
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_tou_pv_10kW_retail
    # FIXME why does switching to retail not change anything?
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Time-of-Use Rate'
    @args_hash['pv_annual_excess_sellback_rate_type'] = 'Retail Electricity Cost'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 376
    @expected_bills['Electricity: PV Credit ($)'] = -376
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_tou_pv_1kW_feed_in_tariff
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Time-of-Use Rate'
    @args_hash['pv_compensation_type'] = 'Feed-In Tariff'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 376
    @expected_bills['Electricity: PV Credit ($)'] = -178
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_tou_pv_10kW_feed_in_tariff
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Time-of-Use Rate'
    @args_hash['pv_compensation_type'] = 'Feed-In Tariff'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 376
    @expected_bills['Electricity: PV Credit ($)'] = -1786
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_tou_pv_1kW_grid_fee_dollars_per_kW
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Time-of-Use Rate'
    @args_hash['pv_monthly_grid_connection_fee'] = 2.50
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 138
    @expected_bills['Electricity: Marginal ($)'] = 376
    @expected_bills['Electricity: PV Credit ($)'] = -107
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_tiered_tou_pv_1kW_grid_fee_dollars
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Time-of-Use Rate'
    @args_hash['pv_grid_connection_fee_units'] = '$'
    @args_hash['pv_monthly_grid_connection_fee'] = 7.50
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 198
    @expected_bills['Electricity: Marginal ($)'] = 376
    @expected_bills['Electricity: PV Credit ($)'] = -107
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  # Real-time Pricing

  def test_detailed_calculations_sample_real_time_pricing_pv_none
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Real-Time Pricing Rate'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_None.csv')
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, [])
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 352
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_1kW
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Real-Time Pricing Rate'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 352
    @expected_bills['Electricity: PV Credit ($)'] = -104 # FIXME 107
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_10kW
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Real-Time Pricing Rate'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 352
    @expected_bills['Electricity: PV Credit ($)'] = -641
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_10kW_retail
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Real-Time Pricing Rate'
    @args_hash['pv_annual_excess_sellback_rate_type'] = 'Retail Electricity Cost'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 352
    @expected_bills['Electricity: PV Credit ($)'] = -1047 # FIXME 1070
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_1kW_feed_in_tariff
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Real-Time Pricing Rate'
    @args_hash['pv_compensation_type'] = 'Feed-In Tariff'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 352
    @expected_bills['Electricity: PV Credit ($)'] = -178
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_10kW_feed_in_tariff
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Real-Time Pricing Rate'
    @args_hash['pv_compensation_type'] = 'Feed-In Tariff'
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_10kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 108
    @expected_bills['Electricity: Marginal ($)'] = 352
    @expected_bills['Electricity: PV Credit ($)'] = -1786
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_1kW_grid_fee_dollars_per_kW
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Real-Time Pricing Rate'
    @args_hash['pv_monthly_grid_connection_fee'] = 2.50
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 138
    @expected_bills['Electricity: Marginal ($)'] = 352
    @expected_bills['Electricity: PV Credit ($)'] = -104 # FIXME 107
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_1kW_grid_fee_dollars
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Real-Time Pricing Rate'
    @args_hash['pv_grid_connection_fee_units'] = '$'
    @args_hash['pv_monthly_grid_connection_fee'] = 7.50
    fuels, utility_rates, utility_bills = @measure.setup_outputs()
    _load_timeseries(fuels, '../tests/PV_1kW.csv')
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems)
    assert(File.exist?(@measure_bills_csv))
    actual_bills = _get_actual_bills(@measure_bills_csv)
    @expected_bills['Electricity: Fixed ($)'] = 198
    @expected_bills['Electricity: Marginal ($)'] = 352
    @expected_bills['Electricity: PV Credit ($)'] = -104 # FIXME 107
    expected_bills = _get_expected_bills(@expected_bills)
    _check_bills(expected_bills, actual_bills)
  end

  # Workflow Tests

  def test_workflow_detailed_calculations
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'User-Specified'
    @args_hash['electricity_utility_rate_user_specified'] = '../../ReportUtilityBills/resources/rates/5a0b28045457a3ea2aca608e.json'
    _test_workflow()
    assert(File.exist?(@workflow_bills_csv))
    actual_bills = _get_actual_bills(@workflow_bills_csv)
    assert_operator(actual_bills['Electricity: Total ($)'], :>, 0)
  end

  def test_workflow_wood_cord
    @args_hash['hpxml_path'] = '../workflow/sample_files/base-hvac-furnace-wood-only.xml'
    @args_hash['wood_cord_marginal_rate'] = 0.0500
    _test_workflow()
    assert(File.exist?(@workflow_bills_csv))
    actual_bills = _get_actual_bills(@workflow_bills_csv)
    assert_operator(actual_bills['Wood Cord: Total ($)'], :>, 0)
  end

  def test_workflow_wood_pellets
    @args_hash['hpxml_path'] = '../workflow/sample_files/base-hvac-stove-wood-pellets-only.xml'
    @args_hash['wood_pellets_marginal_rate'] = 0.0500
    _test_workflow()
    assert(File.exist?(@workflow_bills_csv))
    actual_bills = _get_actual_bills(@workflow_bills_csv)
    assert_operator(actual_bills['Wood Pellets: Total ($)'], :>, 0)
  end

  def test_workflow_coal
    @args_hash['hpxml_path'] = '../workflow/sample_files/base-hvac-furnace-coal-only.xml'
    @args_hash['coal_marginal_rate'] = 0.0500
    _test_workflow()
    assert(File.exist?(@workflow_bills_csv))
    actual_bills = _get_actual_bills(@workflow_bills_csv)
    assert_operator(actual_bills['Coal: Total ($)'], :>, 0)
  end

  def test_workflow_simple_leap_year
    @args_hash['hpxml_path'] = '../workflow/sample_files/base-location-AMY-2012.xml'
    _test_workflow()
    assert(File.exist?(@workflow_bills_csv))
    actual_bills = _get_actual_bills(@workflow_bills_csv)
    assert_operator(actual_bills['Total ($)'], :>, 0)
  end

  def test_workflow_detailed_leap_year
    @args_hash['hpxml_path'] = '../workflow/sample_files/base-location-AMY-2012.xml'
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'Sample Tiered Rate'
    _test_workflow()
    assert(File.exist?(@workflow_bills_csv))
    actual_bills = _get_actual_bills(@workflow_bills_csv)
    assert_operator(actual_bills['Total ($)'], :>, 0)
  end

  def test_workflow_semi_annual_run_period
    @args_hash['hpxml_path'] = '../workflow/sample_files/base-simcontrol-runperiod-1-month.xml'
    _test_workflow()
    assert(File.exist?(@workflow_bills_csv))
    actual_bills = _get_actual_bills(@workflow_bills_csv)
    assert_operator(actual_bills['Total ($)'], :>, 0)
  end

  def test_auto_marginal_rate
    fuel_types = [FT::Elec, FT::Gas, FT::Oil, FT::Propane]

    # Check that we can successfully look up "auto" rates for every state
    # and every fuel type.
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    Constants.StateCodesMap.keys.each do |state_code|
      fuel_types.each do |fuel_type|
        flatratebuy = @measure.get_auto_marginal_rate(runner, state_code, fuel_type, 0)
        refute_nil(flatratebuy)
      end
    end

    # Check that any other state code is gracefully handled (no error)
    fuel_types.each do |fuel_type|
      @measure.get_auto_marginal_rate(runner, 'XX', fuel_type, 0)
    end
  end

  def test_warning_region
    @args_hash['hpxml_path'] = '../workflow/sample_files/base-appliances-oil-location-miami-fl.xml'
    expected_warnings = ['Could not find state average Fuel Oil rate based on Florida; using region (PADD 1C) average.']
    _test_workflow(expected_warnings: expected_warnings)
    assert(File.exist?(@workflow_bills_csv))
  end

  def test_warning_national
    @args_hash['hpxml_path'] = '../workflow/sample_files/base-appliances-propane-location-portland-or.xml'
    expected_warnings = ['Could not find state average Propane rate based on Oregon; using national average.']
    _test_workflow(expected_warnings: expected_warnings)
    assert(File.exist?(@workflow_bills_csv))
  end

  def test_warning_dse
    @args_hash['hpxml_path'] = '../workflow/sample_files/base-hvac-dse.xml'
    expected_warnings = ['DSE is not currently supported when calculating utility bills.']
    _test_workflow(expected_warnings: expected_warnings)
    assert(!File.exist?(@workflow_bills_csv))
  end

  def test_warning_no_rates
    @args_hash['hpxml_path'] = '../workflow/sample_files/base-location-capetown-zaf.xml'
    expected_warnings = ['Could not find a marginal Electricity rate.', 'Could not find a marginal Natural Gas rate.']
    _test_workflow(expected_warnings: expected_warnings)
    assert(!File.exist?(@workflow_bills_csv))
  end

  def test_warning_detailed_semi_annual_simulation
    @args_hash['hpxml_path'] = '../workflow/sample_files/base-simcontrol-runperiod-1-month.xml'
    @args_hash['electricity_bill_type'] = 'Detailed'
    expected_warnings = ['A full annual simulation is required for calculating detailed utility bills.']
    _test_workflow(expected_warnings: expected_warnings)
    assert(!File.exist?(@workflow_bills_csv))
  end

  def test_warning_detailed_no_utility_rate_type
    @args_hash['electricity_bill_type'] = 'Detailed'
    expected_warnings = ['Must specify a utility rate type when calculating detailed utility bills.']
    _test_workflow(expected_warnings: expected_warnings)
    assert(!File.exist?(@workflow_bills_csv))
  end

  def test_warning_user_specified_but_no_rates
    @args_hash['electricity_bill_type'] = 'Detailed'
    @args_hash['electricity_utility_rate_type'] = 'User-Specified'
    expected_warnings = ['Must specify a utility rate json path when choosing User-Specified utility rate type.']
    _test_workflow(expected_warnings: expected_warnings)
    assert(!File.exist?(@workflow_bills_csv))
  end

  def test_monthly_prorate
    # Test begin_month == end_month
    header = HPXML::Header.new(nil)
    header.sim_begin_month = 3
    header.sim_begin_day = 5
    header.sim_end_month = 3
    header.sim_end_day = 20
    header.sim_calendar_year = 2002
    assert_equal(0.0, CalculateUtilityBill.calculate_monthly_prorate(header, 2))
    assert_equal((20 - 5 + 1) / 31.0, CalculateUtilityBill.calculate_monthly_prorate(header, 3))
    assert_equal(0.0, CalculateUtilityBill.calculate_monthly_prorate(header, 4))

    # Test begin_month != end_month
    header = HPXML::Header.new(nil)
    header.sim_begin_month = 2
    header.sim_begin_day = 10
    header.sim_end_month = 4
    header.sim_end_day = 10
    header.sim_calendar_year = 2002
    assert_equal(0.0, CalculateUtilityBill.calculate_monthly_prorate(header, 1))
    assert_equal((28 - 10 + 1) / 28.0, CalculateUtilityBill.calculate_monthly_prorate(header, 2))
    assert_equal(1.0, CalculateUtilityBill.calculate_monthly_prorate(header, 3))
    assert_equal(10 / 30.0, CalculateUtilityBill.calculate_monthly_prorate(header, 4))
    assert_equal(0.0, CalculateUtilityBill.calculate_monthly_prorate(header, 5))
  end

  def _get_actual_bills(bills_csv)
    actual_bills = {}
    File.readlines(bills_csv).each do |line|
      next if line.strip.empty?

      key, value = line.split(',').map { |x| x.strip }
      actual_bills[key] = Float(value)
    end
    return actual_bills
  end

  def _get_expected_bills(expected_bills)
    expected_bills['Electricity: Total ($)'] = expected_bills['Electricity: Fixed ($)'] + expected_bills['Electricity: Marginal ($)'] + expected_bills['Electricity: PV Credit ($)']
    expected_bills['Natural Gas: Total ($)'] = expected_bills['Natural Gas: Fixed ($)'] + expected_bills['Natural Gas: Marginal ($)']
    expected_bills['Total ($)'] = expected_bills['Electricity: Total ($)'] + expected_bills['Natural Gas: Total ($)'] + expected_bills['Fuel Oil: Total ($)'] + expected_bills['Propane: Total ($)'] + expected_bills['Wood Cord: Total ($)'] + expected_bills['Wood Pellets: Total ($)'] + expected_bills['Coal: Total ($)']
    return expected_bills
  end

  def _check_bills(expected_bills, actual_bills)
    bills = expected_bills.keys | actual_bills.keys
    bills.each do |bill|
      assert(expected_bills.keys.include?(bill))
      assert(actual_bills.keys.include?(bill))
      assert_in_delta(expected_bills[bill], actual_bills[bill], 1) # within a dollar
    end
  end

  def _load_timeseries(fuels, path)
    columns = CSV.read(File.join(File.dirname(__FILE__), path)).transpose
    columns.each do |col|
      col_name = col[0]
      next if col_name == 'Date/Time'

      values = col[1..-1].map { |v| Float(v) }

      if col_name == 'ELECTRICITY:UNIT_1 [J](Hourly)'
        fuel = fuels[[FT::Elec, false]]
        unit_conv = UnitConversions.convert(1.0, 'J', fuel.units)
        fuel.timeseries = values.map { |v| v * unit_conv }
      elsif col_name == 'GAS:UNIT_1 [J](Hourly)'
        fuel = fuels[[FT::Gas, false]]
        unit_conv = UnitConversions.convert(1.0, 'J', fuel.units)
        fuel.timeseries = values.map { |v| v * unit_conv }
      elsif col_name == 'Appl_1:ExteriorEquipment:Propane [J](Hourly)'
        fuel = fuels[[FT::Propane, false]]
        unit_conv = UnitConversions.convert(1.0, 'J', fuel.units) / 91.6
        fuel.timeseries = values.map { |v| v * unit_conv }
      elsif col_name == 'FUELOIL:UNIT_1 [m3](Hourly)'
        fuel = fuels[[FT::Oil, false]]
        unit_conv = UnitConversions.convert(1.0, 'm^3', 'gal')
        fuel.timeseries = values.map { |v| v * unit_conv }
      elsif col_name == 'PV:ELECTRICITY_1 [J](Hourly) '
        fuel = fuels[[FT::Elec, true]]
        unit_conv = UnitConversions.convert(1.0, 'J', fuel.units)
        fuel.timeseries = values.map { |v| v * unit_conv }
      end
    end

    fuels.values.each do |fuel|
      fuel.timeseries = [0] * fuels[[FT::Elec, false]].timeseries.size if fuel.timeseries.empty?
    end

    # Convert hourly data to monthly data
    num_days_in_month = Constants.NumDaysInMonths(2002) # Arbitrary non-leap year
    fuels.each do |(fuel_type, _is_production), fuel|
      next unless fuel_type != FT::Elec || @args_hash['electricity_bill_type'] != 'Detailed'

      ts_data = fuel.timeseries.dup
      fuel.timeseries = []
      start_day = 0
      num_days_in_month.each do |num_days|
        fuel.timeseries << ts_data[start_day * 24..(start_day + num_days) * 24 - 1].sum
        start_day += num_days
      end
    end
  end

  def _bill_calcs(fuels, utility_rates, utility_bills, header, pv_systems)
    args = Hash[@args_hash.collect { |k, v| [k.to_sym, v] }]
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    output_format = 'csv'
    output_path = File.join(File.dirname(__FILE__), "results_bills.#{output_format}")

    @measure.get_utility_rates(@hpxml_path, fuels, utility_rates, args, header.state_code, pv_systems)
    @measure.get_utility_bills(fuels, utility_rates, utility_bills, args, header)
    @measure.get_annual_bills(utility_bills)

    @measure.write_output(runner, utility_bills, output_format, output_path)
  end

  def _test_workflow(expected_errors: [], expected_warnings: [])
    # Run measure via OSW
    require 'json'
    workflow = OpenStudio::WorkflowJSON.new(@template_osw)
    json = JSON.parse(workflow.to_s)

    # Update measure args
    steps = OpenStudio::WorkflowStepVector.new
    found_args = []
    json['steps'].each do |json_step|
      step = OpenStudio::MeasureStep.new(json_step['measure_dir_name'])
      json_step['arguments'].each do |json_arg_name, json_arg_val|
        if @args_hash.keys.include? json_arg_name
          # Override value
          found_args << json_arg_name
          json_arg_val = @args_hash[json_arg_name]
        end
        step.setArgument(json_arg_name, json_arg_val)
      end
      if json_step['measure_dir_name'] == 'ReportUtilityBills'
        @args_hash.each do |arg_name, arg_val|
          if !found_args.include?(arg_name)
            step.setArgument(arg_name, arg_val)
            found_args << arg_name
          end
        end
      end
      steps.push(step)
    end

    workflow.setWorkflowSteps(steps)
    osw_path = File.join(File.dirname(@template_osw), 'test.osw')
    workflow.saveAs(osw_path)
    assert_equal(@args_hash.size, found_args.size)

    # Run OSW
    command = "#{OpenStudio.getOpenStudioCLI} run -w #{osw_path}"
    cli_output = `#{command}`

    # Cleanup
    File.delete(osw_path)

    # check warnings/errors
    if not expected_errors.empty?
      expected_errors.each do |expected_error|
        assert(cli_output.include?("ERROR] #{expected_error}"))
      end
    end
    if not expected_warnings.empty?
      expected_warnings.each do |expected_warning|
        assert(cli_output.include?("WARN] #{expected_warning}"))
      end
    end
  end
end
