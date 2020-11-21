/**
 * @file
 * Implements Bands strategy based on the Bollinger Bands indicator.
 */

// Includes.
#include <EA31337-classes/Indicators/Indi_Bands.mqh>
#include <EA31337-classes/Strategy.mqh>

// User input params.
INPUT float Bands_LotSize = 0;                // Lot size
INPUT int Bands_SignalOpenMethod = 0;         // Signal open method (-63-63)
INPUT float Bands_SignalOpenLevel = 18;       // Signal open level (-49-49)
INPUT int Bands_SignalOpenFilterMethod = 18;  // Signal open filter method (-49-49)
INPUT int Bands_SignalOpenBoostMethod = 18;   // Signal open boost method (-49-49)
INPUT int Bands_SignalCloseMethod = 0;        // Signal close method (-63-63)
INPUT float Bands_SignalCloseLevel = 18;      // Signal close level (-49-49)
INPUT int Bands_PriceLimitMethod = 0;         // Price limit method (0-6)
INPUT float Bands_PriceLimitLevel = 10;       // Price limit level
INPUT int Bands_TickFilterMethod = 0;         // Tick filter method
INPUT float Bands_MaxSpread = 0;              // Max spread to trade (pips)
INPUT int Bands_Shift = 0;                    // Shift (relative to the current bar, 0 - default)
INPUT string __Bands_Indi_Bands_Parameters__ =
    "-- Bands strategy: Bands indicator params --";               // >>> Bands strategy: Bands indicator <<<
INPUT int Indi_Bands_Period = 2;                                  // Period
INPUT float Indi_Bands_Deviation = 0.3f;                          // Deviation
INPUT int Indi_Bands_HShift = 0;                                  // Horizontal shift
INPUT ENUM_APPLIED_PRICE Indi_Bands_Applied_Price = PRICE_CLOSE;  // Applied Price

// Structs.

// Defines struct with default user indicator values.
struct Indi_Bands_Params_Defaults : BandsParams {
  Indi_Bands_Params_Defaults()
      : BandsParams(::Indi_Bands_Period, ::Indi_Bands_Deviation, ::Indi_Bands_HShift, ::Indi_Bands_Applied_Price) {}
} indi_bands_defaults;

// Defines struct to store indicator parameter values.
struct Indi_Bands_Params : public BandsParams {
  // Struct constructors.
  void Indi_Bands_Params(BandsParams &_params, ENUM_TIMEFRAMES _tf) : BandsParams(_params, _tf) {}
};

// Defines struct with default user strategy values.
struct Stg_Bands_Params_Defaults : StgParams {
  Stg_Bands_Params_Defaults()
      : StgParams(::Bands_SignalOpenMethod, ::Bands_SignalOpenFilterMethod, ::Bands_SignalOpenLevel,
                  ::Bands_SignalOpenBoostMethod, ::Bands_SignalCloseMethod, ::Bands_SignalCloseLevel,
                  ::Bands_PriceLimitMethod, ::Bands_PriceLimitLevel, ::Bands_TickFilterMethod, ::Bands_MaxSpread,
                  ::Bands_Shift) {}
} stg_bands_defaults;

// Struct to define strategy parameters to override.
struct Stg_Bands_Params : StgParams {
  Indi_Bands_Params iparams;
  StgParams sparams;

  // Struct constructors.
  Stg_Bands_Params(Indi_Bands_Params &_iparams, StgParams &_sparams)
      : iparams(indi_bands_defaults, _iparams.tf), sparams(stg_bands_defaults) {
    iparams = _iparams;
    sparams = _sparams;
  }
};

// Loads pair specific param values.
#include "config/EURUSD_H1.h"
#include "config/EURUSD_H4.h"
#include "config/EURUSD_H8.h"
#include "config/EURUSD_M1.h"
#include "config/EURUSD_M15.h"
#include "config/EURUSD_M30.h"
#include "config/EURUSD_M5.h"

class Stg_Bands : public Strategy {
 public:
  Stg_Bands(StgParams &_params, string _name) : Strategy(_params, _name) {}

  static Stg_Bands *Init(ENUM_TIMEFRAMES _tf = NULL, long _magic_no = NULL, ENUM_LOG_LEVEL _log_level = V_INFO) {
    // Initialize strategy initial values.
    Indi_Bands_Params _indi_params(indi_bands_defaults, _tf);
    StgParams _stg_params(stg_bands_defaults);
    if (!Terminal::IsOptimization()) {
      SetParamsByTf<Indi_Bands_Params>(_indi_params, _tf, indi_bands_m1, indi_bands_m5, indi_bands_m15, indi_bands_m30,
                                       indi_bands_h1, indi_bands_h4, indi_bands_h8);
      SetParamsByTf<StgParams>(_stg_params, _tf, stg_bands_m1, stg_bands_m5, stg_bands_m15, stg_bands_m30, stg_bands_h1,
                               stg_bands_h4, stg_bands_h8);
    }
    // Initialize indicator.
    BandsParams bands_params(_indi_params);
    _stg_params.SetIndicator(new Indi_Bands(_indi_params));
    // Initialize strategy parameters.
    _stg_params.GetLog().SetLevel(_log_level);
    _stg_params.SetMagicNo(_magic_no);
    _stg_params.SetTf(_tf, _Symbol);
    // Initialize strategy instance.
    Strategy *_strat = new Stg_Bands(_stg_params, "Bands");
    _stg_params.SetStops(_strat, _strat);
    return _strat;
  }

  /**
   * Check strategy's opening signal.
   */
  bool SignalOpen(ENUM_ORDER_TYPE _cmd, int _method = 0, float _level = 0.0) {
    Chart *_chart = sparams.GetChart();
    Indi_Bands *_indi = Data();
    bool _is_valid = _indi[CURR].IsValid() && _indi[PREV].IsValid() && _indi[PPREV].IsValid();
    bool _result = _is_valid;
    if (!_result) {
      // Returns false when indicator data is not valid.
      return false;
    }
    double level = _level * Chart().GetPipSize();
    switch (_cmd) {
      // Buy: price crossed lower line upwards (returned to it from below).
      case ORDER_TYPE_BUY: {
        // Price value was lower than the lower band.
        double lowest_price = fmin(_chart.GetLow(CURR), fmin(_chart.GetLow(PREV), _chart.GetLow(PPREV)));
        _result = (lowest_price < fmax(fmax(_indi[CURR].value[BAND_LOWER], _indi[PREV].value[BAND_LOWER]),
                                       _indi[PPREV].value[BAND_LOWER])) -
                  level;
        if (_method != 0) {
          if (METHOD(_method, 0)) _result &= fmin(Close[PREV], Close[PPREV]) < _indi[CURR].value[BAND_LOWER];
          if (METHOD(_method, 1)) _result &= (_indi[CURR].value[BAND_LOWER] > _indi[PPREV].value[BAND_LOWER]);
          if (METHOD(_method, 2)) _result &= (_indi[CURR].value[BAND_BASE] > _indi[PPREV].value[BAND_BASE]);
          if (METHOD(_method, 3)) _result &= (_indi[CURR].value[BAND_UPPER] > _indi[PPREV].value[BAND_UPPER]);
          if (METHOD(_method, 4)) _result &= lowest_price < _indi[CURR].value[BAND_BASE];
          if (METHOD(_method, 5)) _result &= Open[CURR] < _indi[CURR].value[BAND_BASE];
          if (METHOD(_method, 6)) _result &= fmin(Close[PREV], Close[PPREV]) > _indi[CURR].value[BAND_BASE];
        }
        break;
      }
      // Sell: price crossed upper line downwards (returned to it from above).
      case ORDER_TYPE_SELL: {
        // Price value was higher than the upper band.
        double highest_price = fmin(_chart.GetHigh(CURR), fmin(_chart.GetHigh(PREV), _chart.GetHigh(PPREV)));
        _result = (highest_price > fmin(fmin(_indi[CURR].value[BAND_UPPER], _indi[PREV].value[BAND_UPPER]),
                                        _indi[PPREV].value[BAND_UPPER])) +
                  level;
        if (_method != 0) {
          if (METHOD(_method, 0)) _result &= fmin(Close[PREV], Close[PPREV]) > _indi[CURR].value[BAND_UPPER];
          if (METHOD(_method, 1)) _result &= (_indi[CURR].value[BAND_LOWER] < _indi[PPREV].value[BAND_LOWER]);
          if (METHOD(_method, 2)) _result &= (_indi[CURR].value[BAND_BASE] < _indi[PPREV].value[BAND_BASE]);
          if (METHOD(_method, 3)) _result &= (_indi[CURR].value[BAND_UPPER] < _indi[PPREV].value[BAND_UPPER]);
          if (METHOD(_method, 4)) _result &= highest_price > _indi[CURR].value[BAND_BASE];
          if (METHOD(_method, 5)) _result &= Open[CURR] > _indi[CURR].value[BAND_BASE];
          if (METHOD(_method, 6)) _result &= fmin(Close[PREV], Close[PPREV]) < _indi[CURR].value[BAND_BASE];
        }
        break;
      }
    }
    return _result;
  }

  /**
   * Gets price limit value for profit take or stop loss.
   */
  float PriceLimit(ENUM_ORDER_TYPE _cmd, ENUM_ORDER_TYPE_VALUE _mode, int _method = 0, float _level = 0.0) {
    Indi_Bands *_indi = Data();
    double _trail = _level * Market().GetPipSize();
    int _direction = Order::OrderDirection(_cmd, _mode);
    double _default_value = Market().GetCloseOffer(_cmd) + _trail * _direction;
    double _result = _default_value;
    switch (_method) {
      case 0:
        _result =
            (_direction > 0 ? _indi[CURR].value[BAND_UPPER] : _indi[CURR].value[BAND_LOWER]) + _trail * _direction;
        break;
      case 1:
        _result =
            (_direction > 0 ? _indi[PREV].value[BAND_UPPER] : _indi[PREV].value[BAND_LOWER]) + _trail * _direction;
        break;
      case 2:
        _result =
            (_direction > 0 ? _indi[PPREV].value[BAND_UPPER] : _indi[PPREV].value[BAND_LOWER]) + _trail * _direction;
        break;
      case 3:
        _result = (_direction > 0 ? fmax(_indi[PREV].value[BAND_UPPER], _indi[PPREV].value[BAND_UPPER])
                                  : fmin(_indi[PREV].value[BAND_LOWER], _indi[PPREV].value[BAND_LOWER])) +
                  _trail * _direction;
        break;
      case 4:
        _result = _indi[CURR].value[BAND_BASE] + _trail * _direction;
        break;
      case 5:
        _result = _indi[PREV].value[BAND_BASE] + _trail * _direction;
        break;
      case 6:
        _result = _indi[PPREV].value[BAND_BASE] + _trail * _direction;
        break;
      case 7: {
        int _bar_count = (int)_level * (int)_indi.GetPeriod();
        _result = _direction > 0 ? _indi.GetPrice(PRICE_HIGH, _indi.GetHighest(_bar_count))
                                 : _indi.GetPrice(PRICE_LOW, _indi.GetLowest(_bar_count));
        break;
      }
    }
    return (float)_result;
  }
};
